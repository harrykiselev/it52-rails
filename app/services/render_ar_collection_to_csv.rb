class RenderARCollectionToCsv
  def self.perform(collection, column_names = nil, options = {})
    column_names = column_names || collection.table_name.singularize.capitalize.constantize.column_names

    CSV.generate(options) do |csv|
      csv << column_names
      collection.each do |collection_item|
        csv << collection_item.attributes.values_at(*column_names)
      end
    end
  end
end
