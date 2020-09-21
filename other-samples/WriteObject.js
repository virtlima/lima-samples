var AWS = require('aws-sdk'), s3 = new AWS.S3();
const response = require("cfn-response");
exports.handler = async (event, context) => {
  function postResponse(event, context, status, data){
      return new Promise((resolve, reject) => {
          setTimeout(() => response.send(event, context, status, data), 5000)
      });
  }
  function emptyBucket(bucketName,dir,callback){
    var params = {
      Bucket: bucketName,
      Prefix: dir
    };
  
    s3.listObjects(params, function(err, data) {
      if (err) return callback(err);
  
      if (data.Contents.length == 0) callback();
  
      params = {Bucket: bucketName};
      params.Delete = {Objects:[]};
  
      data.Contents.forEach(function(content) {
        params.Delete.Objects.push({Key: content.Key});
      });
  
      s3.deleteObjects(params, function(err, data) {
        if (err) return callback(err);
        if(data.Contents.length == 1000)emptyBucket(bucketName,callback);
        else callback();
      });
    });
  }
  console.log(JSON.stringify(event));
  if (event.RequestType === 'Delete') {
    await s3.deleteObject({
      Bucket: event.ResourceProperties.Bucket,
      Key: event.ResourceProperties.Key
    }).promise();
    emptyBucket(event.ResourceProperties.Bucket, 'logs/');
    await postResponse(event, context, response.SUCCESS, {});
    return;
  }
  await s3.putObject({
    Body: event.ResourceProperties.Body,
    Bucket: event.ResourceProperties.Bucket,
    Key: event.ResourceProperties.Key
  }).promise();
  await postResponse(event, context, response.SUCCESS, {});
};