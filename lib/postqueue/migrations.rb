module Postqueue
  module Migrations
    private

    def connection
      ActiveRecord::Base.connection
    end

    def create_postqueue_table!(fq_table_name)
      return if connection.has_table?(table_name: fq_table_name)

      Postqueue.logger.info "[#{fq_table_name}] Create table"
      quoted_table_name = connection.quote_fq_identifier(fq_table_name)

      schema, table_name = connection.parse_fq_name(fq_table_name)
      if schema
        connection.execute <<-SQL
          CREATE SCHEMA IF NOT EXISTS #{connection.quote_fq_identifier schema}
        SQL
      end

      connection.execute <<-SQL
        CREATE TABLE #{quoted_table_name} (
          id          BIGSERIAL PRIMARY KEY,
          op          VARCHAR,
          queue       VARCHAR,
          entity_id   INTEGER NOT NULL DEFAULT 0,
          created_at  timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
          next_run_at timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
          failed_attempts INTEGER NOT NULL DEFAULT 0
        );

        -- This index should be usable to find duplicate duplicates in the table. While
        -- we search for entries with matching op and entity_id, we assume that entity_id
        -- has a much higher cardinality.
        CREATE INDEX #{connection.quote_identifier "#{table_name}_idx1"} ON #{quoted_table_name}(entity_id);

        -- This index should help picking the next entries to run. Otherwise a full tablescan
        -- would be necessary whenevr we check out items.
        CREATE INDEX #{connection.quote_identifier "#{table_name}_idx2"} ON #{quoted_table_name}(next_run_at);
      SQL
    end

    def change_postqueue_id_type!(fq_table_name)
      return if connection.column_type(table_name: fq_table_name, column: "id") == "bigint"

      Postqueue.logger.info "[#{fq_table_name}] Changing type of id column to BIGINT"
      connection.execute <<-SQL
        ALTER TABLE #{connection.quote_fq_identifier fq_table_name} ALTER COLUMN id TYPE BIGINT;
        ALTER SEQUENCE #{connection.quote_fq_identifier "#{fq_table_name}_id_seq"} RESTART WITH 2147483649
      SQL
    end

    def add_postqueue_queue_column!(fq_table_name)
      Postqueue.logger.info "[#{fq_table_name}] Adding queue column"
      connection.execute <<-SQL
        ALTER TABLE #{connection.quote_fq_identifier fq_table_name} ADD COLUMN IF NOT EXISTS queue VARCHAR;
      SQL
    end
  end
end
