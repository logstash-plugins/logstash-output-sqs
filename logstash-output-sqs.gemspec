Gem::Specification.new do |s|
  s.name          = 'logstash-output-sqs'
  s.version       = '3.1.0'
  s.licenses      = ['Apache License (2.0)']
  s.summary       = 'Push events to an Amazon Web Services Simple Queue Service (SQS) queue.'
  s.description   = 'This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program'
  s.homepage      = 'http://www.elastic.co/guide/en/logstash/current/index.html'
  s.authors       = ['Elastic']
  s.email         = 'info@elastic.co'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*', 'spec/**/*', 'vendor/**/*', '*.gemspec', '*.md', 'CONTRIBUTORS', 'Gemfile', 'LICENSE', 'NOTICE.TXT']
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { 'logstash_plugin' => 'true', 'logstash_group' => 'output' }

  # Gem dependencies
  s.add_runtime_dependency 'logstash-core-plugin-api', '>= 1.60', '<= 2.99'
  s.add_runtime_dependency 'logstash-mixin-aws', '>= 1.0.0'
  s.add_runtime_dependency 'stud'
  s.add_development_dependency 'logstash-devutils'

  # I'm not exactly sure why this is necessary, but without explicitly
  # specifying this dependency, the RSpec tests fail with
  # "NameError: missing class name (`org.apache.logging.log4j.Level')".
  s.add_runtime_dependency 'logstash-core', '< 5.1'
end

