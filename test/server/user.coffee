'use strict'
#
# FastChat
# 2015
#

should = require('chai').should()
supertest = require('supertest')
api = supertest('http://localhost:6190')
mongoose = require('mongoose')
User = require('../../lib/model/user')
token = null
createdUser = null
UNAUTHENTICATED_MESSAGE = 'Unauthorized'
AvatarTests = process.env.AWS_KEY? and process.env.AWS_SECRET?

describe 'Users', ->

  before (done)->
    mongoose.connect 'mongodb://localhost/test'
    db = mongoose.connection
    db.once 'open', ->
      User.remove {}, (err)->
        done()

  it 'should fail to register a new user without the proper information', (done)->
    api.post('/user')
    .send({})
    .expect(400)
    .expect('Content-Type', /json/)
    .end (err, res)->
      should.exist(res.body)
      should.exist(res.body.error)
      should.not.exist(err)
      res.body.message.should.contain('username')
      done()


  it 'should allow a user to be registered with a username and password', (done)->
    api.post('/user')
    .send(username: 'test1', password: 'test')
    .expect(201)
    .expect('Content-Type', /json/)
    .end (err, res)->
      should.exist(res.body)
      should.not.exist(err)
      should.exist(res.body.username)
      res.body.username.should.equal('test1')
      res.body.password.should.not.equal('test')
      createdUser = res.body

      User.find (err, users)->
        should.not.exist(err)
        users.should.have.length(1)
        done()

  it 'should not allow you to login without a username and password', (done)->
    api.post('/login')
    .send({})
    .expect(400)
    .expect('Content-Type', /json/)
    .end (err, res)->
      should.not.exist(err)
      should.exist(res.body)
      should.exist(res.body.error)
      done()

  it 'should allow you to login with a username and password', (done)->
    api.post('/login')
      .send(username: 'test1', password: 'test')
      .expect(200)
      .expect('Content-Type', /json/)
      .end (err, res)->
        should.exist(res.body)
        should.not.exist(err)
        should.exist res.body.access_token
        token = res.body.access_token
        done()

  it 'should return a new Access Token if you login again', (done)->
    api.post('/login')
      .send(username: 'test1', password: 'test')
      .end (err, res)->
        token.should.not.equal res.body.access_token
        done()

  it 'should return the user profile', (done)->
    api.get('/user')
      .set('Authorization', "Bearer #{token}")
      .expect(200)
      .expect('Content-Type', /json/)
      .end (err, res)->
        should.exist(res.body)
        createdUser.username.should.equal(res.body.username)
        createdUser.password.should.equal(res.body.password)
        createdUser._id.should.equal(res.body._id)

        # It should have your past groups
        res.body.groups.should.have.length(0)
        res.body.leftGroups.should.have.length(0)
        done()

  it 'should not allow you to logout without a session token', (done)->
    api.del('/logout')
      .expect(401)
      .expect('Content-Type', /json/)
      .end (err, res)->
        should.exist(res.body)
        should.not.exist(err)
        res.body.error.should.contain(UNAUTHENTICATED_MESSAGE)
        done()

  it 'should log you out and remove your session token', (done)->
    arrayLength = -1

    User.findOne _id: createdUser._id, (err, user)->
      should.not.exist(err)
      arrayLength = user.accessToken.length

      api.del('/logout')
        .set('Authorization', "Bearer #{token}")
        .expect(200)
        .expect('Content-Type', /json/)
        .end (err, res)->
          should.exist(res.body)
          should.not.exist(err)

          # did we delete it?
          User.findOne _id: createdUser._id, (err, user)->
            should.not.exist(err)
            newLength = user.accessToken.length
            newLength.should.below(arrayLength)
            (newLength + 1).should.equal(arrayLength)
            done()

  it 'should not let you login with your old session token', (done)->
    api.del('/logout')
      .set('Authorization', "Bearer #{token}")
      .expect(401)
      .expect('Content-Type', /json/)
      .end (err, res)->
        should.not.exist(err)
        res.body.error.should.equal(UNAUTHENTICATED_MESSAGE)
        done()


  it 'should give a 401 on profile request', (done)->
    api.get('/user')
    .set('x-api-key', '123myapikey')
    .auth('incorrect', 'credentials')
    .expect(401, done)

  it 'should return a new Session Token if you login for the last time', (done)->
    api.post('/login')
      .send(username: 'test1', password: 'test')
      .end (err, res)->
        token.should.not.equal res.body.access_token
        token = res.body.access_token
        done()

  it 'logging out of ALL should remove all session tokens', (done)->
    arrayLength = -1

    User.findOne _id: createdUser._id, (err, user)->
      should.not.exist(err)
      arrayLength = user.accessToken.length
      arrayLength.should.equal(2)

      api.del('/logout?all=true')
        .set('Authorization', "Bearer #{token}")
        .expect(200)
        .expect('Content-Type', /json/)
        .end (err, res)->
          should.exist(res.body)
          should.not.exist(err)

          # did we delete it?
          User.findOne _id: createdUser._id, (err, user)->
            should.not.exist(err)
            user.accessToken.should.be.empty
            done()


  it 'should let a user upload an avatar', (done)->
    return done() unless AvatarTests

    api.post('/login')
      .send(username: 'test1', password: 'test')
      .expect(200)
      .expect('Content-Type', /json/)
      .end (err, res)->
        should.exist(res.body)
        should.not.exist(err)
        should.exist res.body.access_token
        token = res.body.access_token

        req = api.post('/user/' + createdUser._id + '/avatar')

        req.set('Authorization', "Bearer #{token}")
        req.attach('avatar', 'test/integration/test_image.png')
        req.end (err, res)->
          res.status.should.equal(200)
          should.not.exist(err)
          should.exist(res.body)
          res.body.should.be.empty
          done()

  it 'should allow the user to download an avatar', (done)->
    return done() unless AvatarTests

    api.get("/user/#{createdUser._id}/avatar")
      .set('Authorization', "Bearer #{token}")
      .expect(200)
      .end (err, res)->
        should.not.exist(err)
        should.exist(res.body)
        done()

  after (done)->
    mongoose.disconnect()
    done()
