module Radiator
  module Type

    # See: https://github.com/xeroc/piston-lib/blob/34a7525cee119ec9b24a99577ede2d54466fca0e/steembase/operations.py
    class Amount < Serializer
      ASSET_PRECISION = {
        'STEEM' => 3,
        'VESTS' => 6,
        'SBD' => 3,
        'GOLOS' => 3,
        'GESTS' => 6,
        'GBG' => 3,
        'CORE' => 3,
        'CESTS' => 6,
        'TEST' => 3,
      }.freeze

      def initialize(value)
        super(:amount, value)

        @amount, @asset = value.strip.split(' ')
        @precision = ASSET_PRECISION.fetch(@asset, 'unknown')
        raise TypeError, "Asset #{@asset} unknown." if @asset == 'unknown'
        raise TypeError, "Amount #{@amount} needs to be with #{@precision} exponent" unless @amount.match?(/\.[0-9]{#{@precision}}/)
      end

      def to_bytes
        asset = @asset.ljust(7, "\x00")
        amount = (@amount.to_f * 10 ** @precision).round

        [amount].pack('q') +
        [@precision].pack('c') +
        asset
      end

      def to_s
        "#{@amount} #{@asset}"
      end
    end
  end
end
