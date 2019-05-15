module ZuoraConnect
  class AppInstance < ZuoraConnect::AppInstanceBase
    default_scope {select(ZuoraConnect::AppInstance.column_names.delete_if {|x| ["catalog_mapping", "catalog"].include?(x) }) }
  end
end
