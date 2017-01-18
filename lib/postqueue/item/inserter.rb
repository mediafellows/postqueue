require "active_record"

module Postqueue
  #
  # Postqueue::Item inserter modules.
  #
  # This source file provides multiple implementations to insert Postqueue::Items. 
  # Which one will be used depends on the "extend XXXInserter" line below. 
  class Item < ActiveRecord::Base
    module ActiveRecordInserter
      def insert_item(op:, entity_id:)
        create!(op: op, entity_id: entity_id)
      end
    end

    module RawInserter
      def insert_sql
        "INSERT INTO #{table_name}(op, entity_id) VALUES($1, $2)"
      end

      def insert_item(op:, entity_id:)
        connection.raw_connection.exec_params(insert_sql, [op, entity_id])
      end
    end

    module PreparedRawInserter
      def insert_sql
        "INSERT INTO #{table_name}(op, entity_id) VALUES($1, $2)"
      end

      def prepared_inserter_statement
        @prepared_inserter_statements ||= {}

        # a prepared connection is PER DATABASE connection. It is not shared across
        # connections, and it is not per thread, since a Thread might use different
        # connections during its lifetime.
        connection_id = connection.raw_connection.object_id
        @prepared_inserter_statements[connection_id] ||= create_prepared_inserter_statement
      end

      # prepares the INSERT statement, and returns its name
      def create_prepared_inserter_statement
        name = "postqueue-insert-#{table_name}"
        connection.raw_connection.prepare(name, insert_sql)
        name
      end

      def insert_item(op:, entity_id:)
        connection.raw_connection.exec_prepared(prepared_inserter_statement, [op, entity_id])
      end
    end

    # extend ActiveRecordInserter   # 600µs per item
    extend RawInserter              # 100µs per item
    #extend PreparedRawInserter     # 50µs per item
  end
end
