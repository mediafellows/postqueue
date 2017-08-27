require "active_record"

module Postqueue
  #
  # An item class.
  class Item < ActiveRecord::Base
    self.table_name = nil
    self.abstract_class = true

    def self.create_item_class(table_name:)
      klass = Class.new(self)
      klass.table_name = table_name

      # We need to give this class a name, otherwise a number of AR operations
      # are really really slow.
      Postqueue::Item.const_set(dynamic_item_class_name, klass)
      klass
    end

    def self.dynamic_item_class_name
      @dynamic_item_class_count ||= 0
      "Dynamic#{@dynamic_item_class_count += 1}"
    end

    def self.postpone(ids)
      connection.exec_query <<-SQL
        UPDATE #{table_name}
          SET failed_attempts = failed_attempts+1,
              next_run_at = next_run_at + power(failed_attempts + 1, 1.5) * interval '10 second'
          WHERE id IN (#{ids.join(',')})
      SQL
    end
  end

  def self.unmigrate!(table_name = "postqueue")
    Item.connection.execute <<-SQL
      DROP TABLE IF EXISTS #{table_name};
    SQL
  end

  def self.upgrade_table!(table_name)
    result = ActiveRecord::Base.connection.exec_query <<-SQL
      SELECT data_type FROM information_schema.columns
      WHERE table_name = '#{table_name}' AND column_name = 'id';
    SQL

    data_type = result.rows.first.first
    return if data_type == 'bigint'

    Postqueue.logger.info "Changing type of #{table_name}.id column to BIGINT"
    Item.connection.execute "ALTER TABLE #{table_name} ALTER COLUMN id TYPE BIGINT"
    Item.connection.execute "ALTER SEQUENCE #{table_name}_id_seq RESTART WITH 2147483649"
    Item.reset_column_information
  end

  def self.migrate!(table_name = "postqueue")
    connection = Item.connection

    if connection.tables.include?(table_name)
      upgrade_table!(table_name)
      return
    end

    Postqueue.logger.info "Create table #{table_name}"

    connection.execute <<-SQL
    CREATE TABLE #{table_name} (
      id          BIGSERIAL PRIMARY KEY,
      op          VARCHAR,
      entity_id   INTEGER NOT NULL DEFAULT 0,
      created_at  timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
      next_run_at timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
      failed_attempts INTEGER NOT NULL DEFAULT 0
    );

    -- This index should be usable to find duplicate duplicates in the table. While
    -- we search for entries with matching op and entity_id, we assume that entity_id
    -- has a much higher cardinality.
    CREATE INDEX #{table_name}_idx1 ON #{table_name}(entity_id);

    -- This index should help picking the next entries to run. Otherwise a full tablescan
    -- would be necessary whenevr we check out items.
    CREATE INDEX #{table_name}_idx2 ON #{table_name}(next_run_at);
    SQL
  end
end

require_relative "item/inserter"
require_relative "item/enqueue"
