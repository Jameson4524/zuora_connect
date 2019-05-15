module ActiveRecord
  module ConnectionAdapters
    class PostgreSQLAdapter < AbstractAdapter
      private
        def load_additional_types(type_map, oids = nil)
          initializer = OID::TypeMapInitializer.new(type_map)
          if supports_ranges?
            query = <<-SQL
              SELECT DISTINCT on (t.typname) t.oid, t.typname, t.typelem, t.typdelim, t.typinput, r.rngsubtype, t.typtype, t.typbasetype
              FROM pg_type as t
              LEFT JOIN pg_range as r ON oid = rngtypid
            SQL
          else
            query = <<-SQL
              SELECT DISTINCT on (t.typname) t.oid, t.typname, t.typelem, t.typdelim, t.typinput, t.typtype, t.typbasetype
              FROM pg_type as t
            SQL
          end

          if oids
            query += "WHERE t.oid::integer IN (%s)" % oids.join(", ")
          else
            query += initializer.query_conditions_for_initial_load(type_map)
          end

          execute_and_clear(query, "SCHEMA", []) do |records|
            initializer.run(records)
          end
        end
    end
  end
end
