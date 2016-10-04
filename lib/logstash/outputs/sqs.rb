# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/plugin_mixins/aws_config"
require "stud/buffer"
require "digest/sha2"

# Push events to an Amazon Web Services Simple Queue Service (SQS) queue.
#
# SQS is a simple, scalable queue system that is part of the 
# Amazon Web Services suite of tools.
#
# Although SQS is similar to other queuing systems like AMQP, it
# uses a custom API and requires that you have an AWS account.
# See http://aws.amazon.com/sqs/ for more details on how SQS works,
# what the pricing schedule looks like and how to setup a queue.
#
# To use this plugin, you *must*:
#
#  * Have an AWS account
#  * Setup an SQS queue
#  * Create an identify that has access to publish messages to the queue.
#
# The "consumer" identity must have the following permissions on the queue:
#
#  * sqs:ChangeMessageVisibility
#  * sqs:ChangeMessageVisibilityBatch
#  * sqs:GetQueueAttributes
#  * sqs:GetQueueUrl
#  * sqs:ListQueues
#  * sqs:SendMessage
#  * sqs:SendMessageBatch
#
# Typically, you should setup an IAM policy, create a user and apply the IAM policy to the user.
# A sample policy is as follows:
# [source,ruby]
#      {
#        "Statement": [
#          {
#            "Sid": "Stmt1347986764948",
#            "Action": [
#              "sqs:ChangeMessageVisibility",
#              "sqs:ChangeMessageVisibilityBatch",
#              "sqs:GetQueueAttributes",
#              "sqs:GetQueueUrl",
#              "sqs:ListQueues",
#              "sqs:SendMessage",
#              "sqs:SendMessageBatch"
#            ],
#            "Effect": "Allow",
#            "Resource": [
#              "arn:aws:sqs:us-east-1:200850199751:Logstash"
#            ]
#          }
#        ]
#      }
#
# See http://aws.amazon.com/iam/ for more details on setting up AWS identities.
#
class LogStash::Outputs::SQS < LogStash::Outputs::Base
  include LogStash::PluginMixins::AwsConfig
  include Stud::Buffer

  config_name "sqs"

  # Name of SQS queue to push messages into. Note that this is just the name of the queue, not the URL or ARN.
  config :queue, :validate => :string, :required => true

  # Set to true if you want send messages to SQS in batches with `batch_send`
  # from the amazon sdk
  config :batch, :validate => :boolean, :default => true

  # If `batch` is set to true, the number of events we queue up for a `batch_send`.
  config :batch_events, :validate => :number, :default => 10

  # If `batch` is set to true, the maximum amount of time between `batch_send` commands when there are pending events to flush.
  config :batch_timeout, :validate => :number, :default => 5

  # The maximum number of bytes for any message sent to SQS. Messages exceeding this value will get truncated.
  config :message_max_size, :validate => :number, :default => (256 * 1024)

  # If true the logstash will give up if SQS throws an exception. Default is to retry ad infinum.
  config :stop_on_fail, :validate => :boolean, :default => false

  public
  def aws_service_endpoint(region)
    return {
        :sqs_endpoint => "sqs.#{region}.amazonaws.com"
    }
  end

  public 
  def register
    require "aws-sdk"

    @sqs = AWS::SQS.new(aws_options_hash)

    if @batch
      if @batch_events > 10
        raise RuntimeError.new(
          "AWS only allows a batch_events parameter of 10 or less"
        )
      elsif @batch_events <= 1
        raise RuntimeError.new(
          "batch_events parameter must be greater than 1 (or its not a batch)"
        )
      end
      buffer_initialize(
        :max_items => @batch_events,
        :max_interval => @batch_timeout,
        :logger => @logger
      )
    end

    begin
      @logger.debug("Connecting to AWS SQS queue '#{@queue}'...")
      @sqs_queue = @sqs.queues.named(@queue)
      @logger.info("Connected to AWS SQS queue '#{@queue}' successfully.")
    rescue Exception => e
      @logger.error("Unable to access SQS queue '#{@queue}': #{e.to_s}")
    end # begin/rescue
  end # def register

  public
  def receive(event)
    message_body = event.to_json
    if message_body.bytesize > @message_max_size
      @logger.warn("Message exceeds max length and will be dropped. Max Bytes: #{@message_max_size}, Total Bytes: #{message_body.bytesize}.")
      return
    end

    begin
      if @batch
        buffer_receive(message_body)
        return
      end
      @sqs_queue.send_message(message_body)
    rescue Exception => e
      @logger.error("Unable to log message '#{@message_body}': #{e.to_s}")
    end
  end # def receive

  # called from Stud::Buffer#buffer_flush when there are events to flush
  def flush(events, close=false)
    queue = []
    bytes = 0

    # breakdown queue so calls to sqs does not exceed a total payload of 256 kb
    events.each do |message_body|
      if (bytes + message_body.bytesize) > (256 * 1024)
        @sqs_queue.batch_send(queue)
        queue = []
        bytes = 0
      else
        queue << message_body
        bytes += message_body.bytesize
      end
    end

    if queue.length > 0
      @sqs_queue.batch_send(queue)
    end
  end

  # called from Stud::Buffer#buffer_flush when there are errors while flushing
  def on_flush_error(error)
    if (@stop_on_fail)
      raise error
    end
  end

  public
  def close
    buffer_flush(:final => true)
  end # def close
end
