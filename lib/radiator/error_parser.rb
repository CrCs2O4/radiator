module Radiator
  class ErrorParser
    include Utils

    attr_reader :response, :error, :error_code, :error_message,
      :api_name, :api_method, :api_params,
      :expiry, :can_retry, :can_reprepare, :trx_id, :debug

    alias expiry? expiry
    alias can_retry? can_retry
    alias can_reprepare? can_reprepare

    REPREPARE_WHITELIST = [
      'is_canonical( c ): signature is not canonical',
      'now < trx.expiration: '
    ]

    DUPECHECK = '(skip & skip_transaction_dupe_check) || trx_idx.indices().get<by_trx_id>().find(trx_id) == trx_idx.indices().get<by_trx_id>().end(): Duplicate transaction check failed'

    REPREPARE_BLACKLIST = [DUPECHECK]

    def initialize(response)
      @response = response

      @error = nil
      @error_code = nil
      @error_message = nil
      @api_name = nil
      @api_method = nil
      @api_params = nil

      @expiry = nil
      @can_retry = nil
      @can_reprepare = nil
      @trx_id = nil
      @debug = nil

      parse_error_response
    end

    def parse_error_response
      if response.nil?
        @expiry = false
        @can_retry = false
        @can_reprepare = false

        return
      end

      @response = JSON[response] if response.class == String

      @error = if !!@response['error']
        response['error']
      else
        response
      end

      begin
        @error_code = @error['data']['code']
        stacks = @error['data']['stack']
        stack_formats = stacks.map { |s| s['format'] }
        stack_datum = stacks.map { |s| s['data'] }
        data_call_method = stack_datum.find { |data| data['call.method'] == 'call' }

        @error_message = stack_formats.reject(&:empty?).join('; ')

        @api_name, @api_method, @api_params = if !!data_call_method
          @api_name = data_call_method['call.params']
        end

        # See if we can recover a transaction id out of this hot mess.
        data_trx_ix = stack_datum.find { |data| !!data['trx_ix'] }
        @trx_id = data_trx_ix['trx_ix'] if !!data_trx_ix

        proccess_error_code(stack_formats)
      rescue => e
        if defined? ap
          ap error_perser_exception: e, original_response: response
        else
          puts({error_perser_exception: e, original_response: response}.inspect)
        end

        @expiry = false
        @can_retry = false
        @can_reprepare = false
      end
    end

    def proccess_error_code(stack_formats)
      case @error_code
        when 10
          @expiry = false
          @can_retry = false
          @can_reprepare = @api_name == 'network_broadcast_api' ? \
            (stack_formats & REPREPARE_WHITELIST).any? : false
        when 13
          @error_message = @error['data']['message']
          @expiry = false
          @can_retry = false
          @can_reprepare = false
        when 3030000
          @error_message = @error['data']['message']
          @expiry = false
          @can_retry = false
          @can_reprepare = false
        when 4030100
          # Code 4030100 is "transaction_expiration_exception: transaction
          # expiration exception".  If we assume the expiration was valid, the
          # node might be bad and needs to be dropped.

          @expiry = true
          @can_retry = true
          @can_reprepare = false
        when 4030200
          # Code 4030200 is "transaction tapos exception".  They are recoverable
          # if the transaction hasn't expired yet.  A tapos exception can be
          # retried in situations where the node is behind and the tapos is
          # based on a block the node doesn't know about yet.

          @expiry = false
          @can_retry = true

          # Allow fall back to reprepare if retry fails.
          @can_reprepare = true
        else
          @expiry = false
          @can_retry = false
          @can_reprepare = false
        end
    end

    def to_s
      if !!error_message && !error_message.empty?
        "#{error_code}: #{error_message}"
      else
        error_code.to_s
      end
    end

    def inspect
      "#<#{self.class.name} [#{to_s}]>"
    end
  end
end
