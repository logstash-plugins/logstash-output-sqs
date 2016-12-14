# encoding: utf-8

require 'logstash/errors'
require 'logstash/namespace'
require 'logstash/outputs/base'
require 'logstash/outputs/sqs/patch'
require 'logstash/plugin_mixins/aws_config'
require 'stud/buffer'

Aws.eager_autoload!

# Push events to an Amazon Web Services (AWS) Simple Queue Service (SQS) queue.
#
# SQS is a simple, scalable queue system that is part of the Amazon Web
# Services suite of tools. Although SQS is similar to other queuing systems
# such as Advanced Message Queuing Protocol (AMQP), it uses a custom API and
# requires that you have an AWS account. See http://aws.amazon.com/sqs/ for
# more details on how SQS works, what the pricing schedule looks like and how
# to setup a queue.
#
# The "consumer" identity must have the following permissions on the queue:
#
#   * `sqs:ChangeMessageVisibility`
#   * `sqs:ChangeMessageVisibilityBatch`
#   * `sqs:GetQueueAttributes`
#   * `sqs:GetQueueUrl`
#   * `sqs:ListQueues`
#   * `sqs:SendMessage`
#   * `sqs:SendMessageBatch`
#
# Typically, you should setup an IAM policy, create a user and apply the IAM
# policy to the user. See http://aws.amazon.com/iam/ for more details on
# setting up AWS identities. A sample policy is as follows:
#
# [source,json]
# {
#   "Statement": [
#     {
#       "Sid": "",
#       "Action": [
#         "sqs:ChangeMessageVisibility",
#         "sqs:ChangeMessageVisibilityBatch",
#         "sqs:GetQueueAttributes",
#         "sqs:GetQueueUrl",
#         "sqs:ListQueues",
#         "sqs:SendMessage",
#         "sqs:SendMessageBatch"
#       ],
#       "Effect": "Allow",
#       "Resource": "arn:aws:sqs:us-east-1:123456789012:my-sqs-queue"
#     }
#   ]
# }
#
class LogStash::Outputs::SQS < LogStash::Outputs::Base
  include LogStash::PluginMixins::AwsConfig::V2
  include Stud::Buffer

  config_name 'sqs'

  # Set to `true` to send messages to SQS in batches. The size of the batch is
  # configurable via `batch_events`.
  config :batch, :validate => :boolean, :default => true

  # The number of events to be sent in each batch. This is only relevant when
  # `batch` is set to `true`.
  config :batch_events, :validate => :number, :default => 10

  # The maximum amount of time between between batch sends when there are
  # pending events to flush. This is only relevant when `batch` is set to
  # `true`.
  config :batch_timeout, :validate => :number, :default => 5

  # The name of the SQS queue to push messages into.
  config :queue, :validate => :string, :required => true

  public
  def register
    require 'aws-sdk'

    @sqs = Aws::SQS::Client.new(aws_options_hash)

    if @batch
      if @batch_events > 10
        raise LogStash::ConfigurationError, 'The maximum batch size is 10 events'
      elsif @batch_events <= 1
        raise LogStash::ConfigurationError, 'The batch size must be greater than 1'
      end

      buffer_initialize(
        :logger => @logger,
        :max_interval => @batch_timeout,
        :max_items => @batch_events
      )
    end

    begin
      @logger.debug('Connecting to AWS SQS queue', :queue => @queue, :region => region)
      @queue_url = @sqs.get_queue_url(:queue_name => @queue)[:queue_url]
      @logger.info('Connected to AWS SQS queue successfully', :queue => @queue, :region => region)
    rescue Aws::SQS::Errors::ServiceError => e
      @logger.error('Failed to connect to Amazon SQS', :error => e)
      raise LogStash::ConfigurationError, 'Verify the SQS queue name and your credentials'
    end
  end

  public
  def receive(event)
    if @batch
      buffer_receive(event.to_json)
    else
      @sqs.send_message(queue_url: @queue_url, message_body: event.to_json)
    end
  end

  # Called from `Stud::Buffer#buffer_flush` when there are events to flush.
  def flush(events, close=false)
    entries = Array.new()
    events.each_with_index do |event, index|
      entries.push(:id => index.to_s, :message_body => event)
    end

    @sqs.send_message_batch(:queue_url => @queue_url, :entries => entries)
  end

  public
  def close
    buffer_flush(:final => true)
  end
end
