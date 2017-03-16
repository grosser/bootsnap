require 'msgpack'
require 'fileutils'
require 'snappy'

module Bootsnap
  module LoadPathCache
    class Store
      NestedTransactionError = Class.new(StandardError)
      SetOutsideTransactionNotAllowed = Class.new(StandardError)

      def initialize(store_path)
        @store_path = store_path
        load_data
      end

      def get(key)
        @data[key]
      end

      def fetch(key)
        raise SetOutsideTransactionNotAllowed unless @in_txn
        v = get(key)
        unless v
          @dirty = true
          v = yield
          @data[key] = v
        end
        v
      end

      def set(key, value)
        raise SetOutsideTransactionNotAllowed unless @in_txn
        if value != @data[key]
          @dirty = true
          @data[key] = value

        end
      end

      def transaction
        raise NestedTransactionError if @in_txn
        @in_txn = true
        yield
      ensure
        commit_transaction
        @in_txn = false
      end

      private

      def commit_transaction
        if @dirty
          dump_data
          @dirty = false
        end
      end

      def load_data
        @data = begin
          MessagePack.load(Snappy.inflate(File.binread(@store_path)))
        rescue Errno::ENOENT, Snappy::Error
          {}
        end
      end

      def dump_data
        # Change contents atomically so other processes can't get invalid
        # caches if they read at an inopportune time.
        tmp = "#{@store_path}.#{(rand * 100000).to_i}.tmp"
        File.binwrite(tmp, Snappy.deflate(MessagePack.dump(@data)))
        FileUtils.mv(tmp, @store_path)
      end
    end
  end
end