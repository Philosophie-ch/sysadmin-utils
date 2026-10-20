## The tables and columns that hold the key of a translation group: every foreign key that points at the key, and every
## column called page_translation_group_key (topics hold it without a foreign key). Found in the database, never listed by hand.
def translation_group_key_references
  connection = ActiveRecord::Base.connection

  foreign_keys = connection.select_rows(<<~SQL)
    SELECT cl.relname, a.attname
    FROM pg_constraint c
    JOIN pg_class cl ON cl.oid = c.conrelid
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.contype = 'f' AND c.confrelid = 'page_translation_groups'::regclass
  SQL

  named_columns = connection.select_rows(<<~SQL)
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = current_schema() AND column_name = 'page_translation_group_key'
  SQL

  return (foreign_keys + named_columns).uniq
end


# A key that is referenced cannot just be updated (the foreign keys do not cascade a rename), so, in one transaction
# (all or nothing), a group with the new key is created, every reference moves to it, and the old group is deleted.
# The group keeps its id and its timestamps: once the old row is gone its id is free, and the new row takes it.
# `references` is the result of translation_group_key_references, found once before the rows are processed. A reference
# that was not found makes the delete fail, and nothing changes.
def rename_translation_group(group, new_key, references)
  connection = ActiveRecord::Base.connection
  old_id = group.id
  renamed = nil

  ActiveRecord::Base.transaction do
    renamed = PageTranslationGroup.create!(key: new_key, created_at: group.created_at, updated_at: group.updated_at)

    references.each do |table, column|
      connection.execute(
        "UPDATE #{connection.quote_table_name(table)} SET #{connection.quote_column_name(column)} = #{connection.quote(new_key)} " \
        "WHERE #{connection.quote_column_name(column)} = #{connection.quote(group.key)}"
      )
    end

    group.destroy!
    connection.execute("UPDATE page_translation_groups SET id = #{old_id.to_i} WHERE id = #{renamed.id.to_i}")
  end

  return PageTranslationGroup.find(old_id)
end
