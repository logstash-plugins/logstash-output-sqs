# encoding: utf-8

require 'logstash/errors'
require 'logstash/event'
require 'spec_helper'

describe LogStash::Outputs::SQS do
  let(:config) do
    {
      'queue' => queue_name,
      'region' => region,
    }
  end
  let(:queue_name) { 'my-sqs-queue' }
  let(:queue_url) { "https://sqs.#{region}.amazonaws.com/123456789012/#{queue_name}" }
  let(:region) { 'us-east-1' }

  let(:mock_sqs) { Aws::SQS::Client.new({ :stub_responses => true }) }
  let(:output) { LogStash::Outputs::SQS.new(config) }
  subject { output }

  describe '#register' do
    context 'with a batch size that is too large' do
      let(:config) { super.merge({ 'batch' => true, 'batch_events' => 100 }) }

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'with a batch size that is too small' do
      let(:config) { super.merge({ 'batch' => true, 'batch_events' => 1 }) }

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'with an invalid batch size and batching disabled' do
      let(:config) { super.merge({ 'batch' => false, 'batch_events' => 100 }) }

      before do
        expect(Aws::SQS::Client).to receive(:new).and_return(mock_sqs)
        expect(mock_sqs).to receive(:get_queue_url).with({ :queue_name => queue_name }).and_return({ :queue_url => queue_url })
      end

      it "doesn't raise a configuration error" do
        expect { subject.register }.not_to raise_error
      end
    end

    context 'with a nonexistent queue' do
      before do
        expect(Aws::SQS::Client).to receive(:new).and_return(mock_sqs)
        expect(mock_sqs).to receive(:get_queue_url).with({ :queue_name => queue_name }) { raise Aws::SQS::Errors::NonExistentQueue.new(nil, 'The specified queue does not exist for this wsdl version.') }
      end

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'with a valid queue' do
      before do
        expect(Aws::SQS::Client).to receive(:new).and_return(mock_sqs)
        expect(mock_sqs).to receive(:get_queue_url).with({ :queue_name => queue_name }).and_return({ :queue_url => queue_url })
      end

      it "doesn't raise an error" do
        expect { subject.register }.not_to raise_error
      end
    end
  end

  describe '#receive' do
    before do
      expect(Aws::SQS::Client).to receive(:new).and_return(mock_sqs)
      expect(mock_sqs).to receive(:get_queue_url).with({ :queue_name => queue_name }).and_return({ :queue_url => queue_url })
      subject.register
    end

    let(:sample_events) do
      sample_data = [
        {
          '@timestamp' => '2014-05-30T02:52:17.929Z',
          'foo' => 'bar',
          'baz' => {
            'bah' => ['a', 'b', 'c'],
          },
        },
        {
          '@timestamp' => '2014-05-30T02:52:17.929Z',
          'foo' => 'bar',
          'baz' => {},
        },
        {
          '@timestamp' => '2014-05-30T02:53:11.763Z',
          'message' => 'This is a message',
        },
        {
          '@timestamp' => '2014-05-30T02:53:11.763Z',
          'message' => 'This is another message',
        },
        {
          '@timestamp' => '2014-05-30T02:53:11.763Z',
          'message' => '',
        },
      ]

      sample_data.each { |data| LogStash::Event.new(data) }
    end

    context 'with batching disabled' do
      let(:config) { super.merge({ 'batch' => false }) }

      it 'should call send_message' do
        sample_events.each do |event|
          expect(mock_sqs).to receive(:send_message).with({ :queue_url => queue_url, message_body: event.to_json }).once
        end

        sample_events.each do |event|
          subject.receive(event)
        end
      end
    end

    context 'with batching enabled' do
      let(:batch_size) { 2 }
      let(:config) { super.merge({ 'batch' => true, 'batch_events' => batch_size, 'batch_timeout' => 1 }) }

      it 'should call send_message_batch' do
        sample_events.each_slice(batch_size).each do |batch|
          entries = batch.each_with_index.map do |event, index|
            {
              :id => index.to_s,
              :message_body => event.to_json,
            }
          end

          expect(mock_sqs).to receive(:send_message_batch).with({ :queue_url => queue_url, entries: entries }).once
        end

        sample_events.each do |event|
          subject.receive(event)
        end

        # We must call `close` to ensure that buffered messages have been flushed.
        subject.close
      end

      it 'should flush events after batch timeout' do
        subject.receive(sample_events[0])
        expect(mock_sqs).to receive(:send_message_batch).with({ :queue_url => queue_url, entries: [{ :id => '0', :message_body => sample_events[0].to_json}] }).once
        sleep 1
        expect(mock_sqs).not_to receive(:send_message_batch)
        subject.close
      end
    end
  end

  describe '#close' do
    before do
      expect(Aws::SQS::Client).to receive(:new).and_return(mock_sqs)
      expect(mock_sqs).to receive(:get_queue_url).with({ :queue_name => queue_name }).and_return({ :queue_url => queue_url })
      subject.register
    end

    it 'should be clean' do
      subject.do_close
    end
  end
end
