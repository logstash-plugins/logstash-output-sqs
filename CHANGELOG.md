## 3.2.0
- Added dynamic batching. Messages will be split into small-enough batches in order to ensure that the total batch size is less than 256KiB.

## 3.1.0
- Update the AWS SDK to version 2.

## 3.0.2
- Relax constraint on `logstash-core-plugin-api` to `>= 1.60 <= 2.99`.

## 3.0.1
- Republish all the gems under JRuby.

## 3.0.0
- Update the plugin to the version 2.0 of the plugin API, this change is
  required for Logstash 5.0 compatibility. See
  https://github.com/elastic/logstash/issues/5141.

## 2.0.5
- Add Travis config and build status.
- Require the AWS mixin to be higher than 1.0.0.

## 2.0.4
- Depend on `logstash-core-plugin-api` instead of `logstash-core`, removing the
  need to mass update plugins on major releases of Logstash.

## 2.0.3
- New dependency requirements for `logstash-core` for the 5.0 release.

## 2.0.0
- Plugins were updated to follow the new shutdown semantic, this mainly allows
  Logstash to instruct input plugins to terminate gracefully, instead of using
  `Thread.raise` on the plugins' threads. Ref
  https://github.com/elastic/logstash/pull/3895.
- Dependency on `logstash-core` updated to 2.0.
