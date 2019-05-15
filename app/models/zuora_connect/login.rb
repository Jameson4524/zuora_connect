module ZuoraConnect
  class Login

    def initialize (fields)
      @clients = {}
      if fields["tenant_type"] == "Zuora"
        login_fields = fields.map{|k,v| [k.to_sym, v]}.to_h
        login_type = fields.dig("authentication_type").blank? ? 'Basic' : fields.dig("authentication_type").capitalize
        
        @clients["Default"] = "::ZuoraAPI::#{login_type}".constantize.new(login_fields)
        @default_entity = fields["entities"][0]["id"] if (fields.dig("entities") || []).size == 1
        if fields["entities"] && fields["entities"].size > 0
          fields["entities"].each do |entity|
            params = {:entity_id => entity["id"]}.merge(login_fields)
            @clients[entity["id"]] =  "::ZuoraAPI::#{login_type}".constantize.new(params)
          end
        end
        self.attr_builder("available_entities", @clients.keys) 
      end
      fields.each do |k,v|
        self.attr_builder(k,v)
      end
      @default_entity ||= "Default"
    end

    def attr_builder(field,val)
      singleton_class.class_eval { attr_accessor "#{field}" }
      send("#{field}=", val)
    end

    def client(id = @default_entity)
      return id.blank? ? @clients[@default_entity] : @clients[id]
    end

  end
end
