'use strict';

class AWSAccount {
  constructor(accountId, displayName) {
    this.id = accountId;
    this.displayName = displayName;
    this.accessKeys = new Map();
  }

  createKeyPair(accessKeyId, secretAccessKey) {
    AWSAccount.registry.set(accessKeyId, this);
    this.accessKeys.set(accessKeyId, secretAccessKey);
  }

  revokeAccessKey(accessKeyId) {
    AWSAccount.registry.delete(accessKeyId);
    this.accessKeys.delete(accessKeyId);
  }
}
AWSAccount.registry = new Map();

exports = module.exports = AWSAccount;

// Hardcoded dummy user used for authenticated requests
exports.DUMMY_ACCOUNT = new AWSAccount(${global_stack_process.customEnv.AMAZON_ACCOUNT_ID}, '${global_stack_process.customEnv.S3RVER_AMAZON_ACCOUNT_DISPLAY_NAME}');
exports.DUMMY_ACCOUNT.createKeyPair('${global_stack_process.customEnv.AWS_ACCESS_KEY_ID}', '${global_stack_process.customEnv.AWS_SECRET_ACCESS_KEY}');
