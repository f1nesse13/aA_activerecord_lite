require_relative "db_connection"
require "active_support/inflector"
# NB: the attr_accessor we wrote in phase 0 is NOT used in the rest
# of this project. It was only a warm up.

class SQLObject
  def self.columns
    return @columns if @columns
    data = DBConnection::execute2(<<-SQL).first
      SELECT * FROM #{self.table_name}
    SQL
    @columns = data.map!(&:to_sym)
  end

  def self.finalize!
    columns.each do |name|
      define_method(name) { attributes[name] }
      define_method("#{name}=") { |val| attributes[name] = val }
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name
  end

  def self.table_name
    @table_name || self.name.underscore.pluralize
  end

  def self.all
    data = DBConnection.execute(<<-SQL)
      SELECT *
      FROM #{self.table_name}
    SQL
    self.parse_all(data)
  end

  def self.parse_all(results)
    results.map { |attrs| self.new(attrs) }
  end

  def self.find(id)
    data = DBConnection.execute(<<-SQL, id)
      SELECT * FROM #{table_name} WHERE id = ?
    SQL
    self.parse_all(data).first
  end

  def initialize(params = {})
    params.each do |attr_name, attr_val|
      attr_name = attr_name.to_sym
      if self.class.columns.include?(attr_name)
        self.send("#{attr_name}=", attr_val)
      else
        raise "unknown attribute '#{attr_name}'"
      end
    end
  end

  def attributes
    @attributes ||= {}
  end

  def attribute_values
    self.class.columns.map { |attr_name| self.send(attr_name) }
  end

  def insert
    columns = self.class.columns[1..-1].join(", ")
    question_marks = (["?"] * self.class.columns[1..-1].length).join(", ")
    DBConnection.execute(<<-SQL, *attribute_values[1..-1])
      INSERT INTO #{self.class.table_name} (#{columns})
      VALUES (#{question_marks})
    SQL
    self.id = DBConnection.last_insert_row_id
  end

  def update
    set_line = self.class.columns[1..-1].map { |attr_name| "#{attr_name} = ?" }.join(", ")
    DBConnection.execute(<<-SQL, *attribute_values.rotate(1))
      UPDATE #{self.class.table_name}
      SET #{set_line}
      WHERE id = ?
    SQL
  end

  def save
    self.id.nil? ? self.insert : self.update
  end
end
