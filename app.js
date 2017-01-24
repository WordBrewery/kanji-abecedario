var express = require('express');
var path = require('path');
var favicon = require('serve-favicon');
var logger = require('morgan');
var cookieParser = require('cookie-parser');
var bodyParser = require('body-parser');
var jwt = require('express-jwt');
var cors = require('cors');
var http = require('http');
require('dotenv').config();

var db = require('./db');

var app = express();
var router = express.Router();
var authenticate = jwt({
  secret : process.env.AUTH0_CLIENT_SECRET,
  audience : process.env.AUTH0_CLIENT_ID
});

app.use(cors());

// uncomment after placing your favicon in /public
// app.use(favicon(__dirname + '/public/favicon.ico'));
app.use(logger('dev'));
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({extended : false}));
app.use(cookieParser());

app.use(express.static('public'));
app.use('/data', express.static('data'))
app.use('/secured', authenticate);

app.use((err, req, res, next) => {
  if (err.name === 'UnauthorizedError') {
    res.status(401).send('unauthorized');
  }
});

app.get('/ping', (req, res) => {
  res.send("All good. You don't need to be authenticated to call this");
});

app.get('/secured/ping', (req, res) => {
  // console.log("user sub to hash", req.user.sub);
  res.status(200).send(
      "All good. You only get this message if you're authenticated");
});

var makeError = (res, errname) => (err => {
  console.error("ERROR SQLite", errname, err);
  res.status(500).send(`database error (${errname})`);
});

// TODO some of these functions in `db` return [], which should 404.

app.get('/secured/record/:target/:deps', (req, res) => {
  db.record(req.params.target, req.user.sub, req.params.deps.split(','))
      .then(_ => res.redirect(`/getTarget/${req.params.target}`))
      .catch(makeError(res, 'record'));
});

app.get('/depsFor/:target', (req, res) => {
  db.depsFor(req.params.target)
      .then(result => res.json(result))
      .catch(makeError(res, 'depsFor'));
});

app.get('/firstNoDeps', (req, res) => {
  db.firstNoDeps()
      .then(result => res.json(result))
      .catch(makeError(res, 'firstNoDeps'));
});

app.get('/secured/userDeps/:target', (req, res) => {
  db.userDeps(req.params.target, req.user.sub)
      .then(result => res.json(result))
      .catch(makeError(res, 'userDeps'));
});

app.get('/getPos/:pos', (req, res) => {
  db.getPos(+req.params.pos)
      .then(result => res.json(result))
      .catch(makeError(res, 'getPos'));
});

app.get('/getTarget/:target', (req, res) => {
  db.getTarget(req.params.target)
      .then(result => res.json(result))
      .catch(makeError(res, 'getTarget'));
});

var port = process.env.PORT || 3000;

http.createServer(app).listen(
    port, (err) => { console.log('listening in http://localhost:' + port); });

module.exports = app;
