var User = require('../model/user');
var Message = require('../model/message');
var GroupSetting = require('../model/groupSetting');
var ObjectId = require('mongoose').Types.ObjectId;
var PER_PAGE = 30;
var multiparty = require('multiparty');
var fs = require('fs');
var uuid = require('uuid');
var knox = require('knox').createClient({
    key: process.env.AWS_KEY,
    secret: process.env.AWS_SECRET,
    bucket: 'com.fastchat.dev.messages'
});

exports.getMessages = function(req, res) {
  console.log('1');

  var idParam = req.params.id.toString();
  var groupId = new ObjectId(idParam);
  var page = req.query.page;
  var usr = req.user;

  if (!page) page = 0;
  
  //MyModel.find(query, fields, { skip: 10, limit: 5 }, function(err, results) { ... });
  Message.find( {group: groupId}, {}, {sort: {sent: -1}, skip: page * PER_PAGE, limit: PER_PAGE}, function(err, messages) {
    console.log('ERR: ' + err);
    
    if (err) return res.send(404, {error: 'Group not found!'});

    ///
    /// Assuming we found the messages, we should also clear the 'unread' count for this group
    ///
    GroupSetting.find({'user': usr._id}, function(err, gses) {
      
      var thisGs = GroupSetting.forGroup(gses, groupId);
      if (thisGs) {
	thisGs.unread = 0;
	usr.push(null, null, GroupSetting.totalUnread(gses), true);
	thisGs.save();
      }
    });

    res.send(messages);
  });
};

//file.media
exports.postMessageData = function(req, res) {
  console.log('2');

  var user = req.user;
  var form = new multiparty.Form();
  var idParam = req.params.id.toString();
  var groupId = new ObjectId(idParam);
  var messageIdParam = req.params.mesId.toString();
  var messageId = new ObjectId(messageIdParam);

  if ( !user.hasGroup(groupId) ) return res.json(404, {'error':'Not Found!'});

  Message.findOne({'_id':messageId}, function(err, message) {
    if (!message) return res.json(404, {'error' : 'Not Found!'});
    if (!message.group.equals(groupId)) return res.json(404, {'error' : 'Not Found!'});
    if (!message.hasMedia) return res.json(400, {'error' : 'This message is not set to have media!'});

    form.parse(req, function(err, fields, files) {
      if (!files) return res.json(400, {'error' : 'File was not successfully uploaded!'});
      if (!files.media) return res.json(400, {'error' : 'Media was not successfully uploaded!'});

      var file = files.media[0]; //for each?
      console.log(file);
      if (!file) return res.json(400, {'error' : 'File was not successfully uploaded!'});

      var stream = fs.createReadStream(file.path)
      var s3req;
      var ext = fileExtension(file.originalFilename);
      var randomName = uuid.v4() + (ext ? ('.' + ext) : '');

      s3req = knox.putStream(stream, randomName, {
	'Content-Type': file.headers['content-type'],
	'Cache-Control': 'max-age=604800',
	'x-amz-acl': 'public-read',
	'Content-Length': file.size
      },
	function(err, result) {

	  if (err) return res.send(400, {'error' : 'THere was an error uploading your image!'});
	  
	  /// Add media name to the message to get later
	  message.media = result.req.path.replace(/^.*[\\\/]/, '');
	  message.mediaHeader = file.headers['content-type'];
	  message.save(function(err) {
	    return res.json(200, {});
	  });
	});

      s3req.on('response', function(s3res){
	if (s3res.statusCode < 200 || s3res.statusCode >= 300) {
	  return res.json(s3res.statusCode, {'error' : 'THere was an error uploading your image!'});
	};

      }); //knox PUT Stream
      s3req.on('error', function(s3err) {
	console.log(s3err);
	console.trace();
      });

    }); //Form Parse
  }); // Find Message In Group
};


exports.getMessageData = function(req, res) {

  var idParam = req.params.id.toString();
  var groupId = new ObjectId(idParam);
  var messageIdParam = req.params.mesId.toString();
  var messageId = new ObjectId(messageIdParam);
  var user = req.user;

  if ( !user.hasGroup(groupId) ) return res.json(404, {'error':'Not Found!'});

  Message.findOne({'_id':messageId}, function(err, message) {
    if (!message) return res.json(404, {'error' : 'Not Found!'});
    if (!message.group.equals(groupId)) return res.json(404, {'error' : 'Not Found!'});
    if (!message.hasMedia) return res.json(400, {'error' : 'This message is not set to have media!'});

    /// User belongs to the group, and the message is in it, and it has media. Get it.

    var data = '';
    knox.get(message.media).on('response', function(s3res){

      if (s3res.statusCode < 200 || s3res.statusCode > 300) {
        return res.send(400, {'error':'There was an error fetching your image!'});
      }

      s3res.setEncoding('binary');
      s3res.on('data', function(chunk){
        data += chunk;
      });

      s3res.on('end', function() {
        res.contentType(message.mediaHeader);
        res.write(data, encoding='binary')
        res.end()
      });
    }).end();

  });//end Find Message
}


function fileExtension(filename) {
  return filename.split('.').pop();
}
