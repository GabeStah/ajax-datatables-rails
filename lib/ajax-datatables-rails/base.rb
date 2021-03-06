module AjaxDatatablesRails
  class Base
    extend Forwardable
    class MethodNotImplementedError < StandardError; end

    attr_reader :view, :options, :sortable_columns, :searchable_columns
    def_delegator :@view, :params, :params

    def initialize(view, options = {})
      @view = view
      @options = options
    end

    def sortable_columns
      @sortable_columns ||= []
    end

    def searchable_columns
      @searchable_columns ||= []
    end

    def data
      fail(
        MethodNotImplementedError,
        'Please implement this method in your class.'
      )
    end

    def get_raw_records
      fail(
        MethodNotImplementedError,
        'Please implement this method in your class.'
      )
    end

    def as_json(options = {})
      {
        :draw => params[:draw].to_i,
        :recordsTotal =>  get_raw_records.count(:all),
        :recordsFiltered => filter_records(get_raw_records).count(:all),
        :data => data
      }
    end

    private

    def records
      @records ||= fetch_records
    end

    def fetch_records
      records = get_raw_records
      records = sort_records(records)
      records = filter_records(records)
      records = paginate_records(records) unless params[:length] == '-1'
      records
    end

    def sort_records(records)
      sort_by = []
      params[:order].each_value do |item|
        sort_by << "#{sort_column(item)} #{sort_direction(item)}"
      end
      records.order(sort_by.join(", "))
    end

    def paginate_records(records)
      fail(
        MethodNotImplementedError,
        'Please mixin a pagination extension.'
      )
    end

    def filter_records(records)
      records = simple_search(records)
      records = composite_search(records)
      records
    end

    def simple_search(records)
      return records unless (params[:search].present? && params[:search][:value].present?)
      conditions = build_conditions_for(params[:search][:value])
      records = records.where(conditions) if conditions
      records
    end

    def composite_search(records)
      conditions = aggregate_query
      records = records.where(conditions) if conditions
      records
    end

    def build_conditions_for(query)
      search_for = query.split(' ')
      criteria = search_for.inject([]) do |criteria, atom|
        criteria << searchable_columns.map { |col| search_condition(col, atom) }.reduce(:or)
      end.reduce(:and)
      criteria
    end

    def search_condition(column, value)
      model, column = column.split('.')
      model = model.singularize.titleize.gsub( / /, '' ).constantize
      casted_column = ::Arel::Nodes::NamedFunction.new('CAST', [model.arel_table[column.to_sym].as(ActiveRecord::Base::connection.is_a?(ActiveRecord::ConnectionAdapters::Mysql2Adapter) ? 'CHAR' : 'VARCHAR')])
      casted_column.matches("%#{value}%")
    end

    def aggregate_query
      conditions = searchable_columns.each_with_index.map do |column, index|
        value = params[:columns]["#{index}"][:search][:value] if params[:columns]
        search_condition(column, value) unless value.blank?
      end
      conditions.compact.reduce(:and)
    end

    def offset
      (page - 1) * per_page
    end

    def page
      (params[:start].to_i / per_page) + 1
    end

    def per_page
      params.fetch(:length, 10).to_i
    end

    def sort_column(item)
      sortable_columns[item['column'].to_i]
    end

    def sort_direction(item)
      options = %w(desc asc)
      options.include?(item['dir']) ? item['dir'].upcase : 'ASC'
    end
  end
end
