# encoding: utf-8

require 'logstash/event'
require 'securerandom'
require 'spec_helper'

describe LogStash::Outputs::SQS, :integration => true do
  let(:config) do
    {
      'queue' => @queue_name,
    }
  end
  subject { LogStash::Outputs::SQS.new(config) }

  # Create an SQS queue with a random name.
  before(:all) do
    @sqs = Aws::SQS::Client.new
    @queue_name = "logstash-output-sqs-#{SecureRandom.hex}"
    @queue_url = @sqs.create_queue(:queue_name => @queue_name)[:queue_url]
  end

  # Destroy the SQS queue which was created in `before(:all)`.
  after(:all) do
    @sqs.delete_queue(:queue_url => @queue_url)
  end

  describe '#register' do
    context 'with invalid credentials' do
      let(:config) do
        super.merge({
          'access_key_id' => 'bad_access',
          'secret_access_key' => 'bad_secret_key',
        })
      end

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'with a nonexistent queue' do
      let(:config) do
        super.merge({
          'queue' => 'queue-does-not-exist',
        })
      end

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'with valid credentials' do
      it "doesn't raise an error" do
        expect { subject.register }.not_to raise_error
      end
    end
  end

  describe '#receive' do
    before do
      subject.register
    end

    after do
      @sqs.purge_queue(:queue_url => @queue_url)
    end

    it 'publishes to SQS' do
      event = LogStash::Event.new()
      subject.receive(event)

      subject.close
      expect(@sqs.receive_message(:queue_url => @queue_url)).not_to be_empty
    end
  end
end
