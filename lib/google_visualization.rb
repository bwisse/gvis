# view helper, and view methods for using the Google Visualization API
#
# For use with rails, include this Module in ApplicationHelper, and call {#include_visualization_api} and {#render_visualizations} within the head tag of your html layout
# See the Readme[http://github.com/jeremyolliver/gvis#readme] for examples and usage details. For more detailed info on each visualization see the API[http://code.google.com/apis/visualization/documentation/]
#
# @author Jeremy Olliver
module GoogleVisualization

  attr_accessor :google_visualizations, :visualization_packages

  # @group Layout helper methods
  # Place these method calls inside the head tag in your layout file.

  # Include the Visualization API code from google.
  # (Omit this call if you prefer to include the API in your own js package)
  def include_visualization_api
    # Ensure we use https when the page is loaded on https so we don't make the page look insecure
    # We would use //www.google.com but the rails helper adds .js onto the end unless we start with an explicit protocol
    if request && request.respond_to?(:scheme)
      protocol = request.scheme
    else
      protocol = 'https' # Best to fall back to https
    end
    javascript_include_tag("#{protocol}://www.google.com/jsapi")
  end

  # Call this method from the within the head tag (or alternately just before the closing body tag)
  # This will render the graph's generated by the rendering of your view files
  # @return [String] a javascript tag that contains the generated javascript to render the graphs
  def render_visualizations
    if @google_visualizations
      package_list = @visualization_packages.uniq.collect do |p|
        package = p.to_s.camelize.downcase
        package = "corechart" if ["areachart", "barchart", "columnchart", "linechart", "piechart", "combochart"].include?(package)
        "\'#{package}\'"
      end
      output = %Q(
        <script type="text/javascript">
          google.load('visualization', '1', {'packages':[#{package_list.uniq.join(',')}]});
          google.setOnLoadCallback(drawCharts);
          var chartData = {};
          var visualizationCharts = {};
          function drawCharts() { )
      @google_visualizations.each do |id, vis|
        output += generate_visualization(id, vis[0], vis[1], vis[2])
      end
      output += "} </script>"
      raw(output + "<!-- Rendered Google Visualizations /-->")
    else
      raw("<!-- No graphs on this page /-->") if debugging?
    end
  end

  # @endgroup Layout helper methods

  # @group View methods

  # Call this method from the view to insert the visualization graph/chart here.
  # This method will output a div with the specified id, and store the chart data to be rendered later via {#render_visualizations}
  # @param [String] id the id of the chart. corresponds to the id of the div
  # @param [String] chart_type the kind of chart to render
  # @param [Hash] options the configuration options for the graph
  def visualization(id, chart_type, options = {}, &block)
    init
    chart_type = chart_type.camelize      # Camelize the chart type, as the Google API follows Camel Case conventions (e.g. ColumnChart, MotionChart)
    options.stringify_keys!               # Ensure consistent hash access
    @visualization_packages << chart_type # Add the chart type to the packages needed to be loaded

    # Initialize the data table (with hashed options), and pass it the block for cleaner adding of attributes within the block
    table = Gvis::DataTable.new(options.delete("data"), options.delete("columns"), options)
    if block_given?
      yield table
    end

    html_options = options.delete("html") || {} # Extract the html options
    @google_visualizations.merge!(id => [chart_type, table, options]) # Store our chart in an instance variable to be rendered in the head tag

    # Output a div with given id on the page right now, that our graph will be embedded into
    html = html_options.collect {|key,value| "#{key}=\"#{value}\"" }.join(" ")
    concat raw(%Q(<div id="#{escape_id(id)}" #{html}><!-- /--></div>))
    nil # Return nil just incase this is called with an output erb tag, as we don't to output the html twice
  end

  # @endgroup View methods

  protected

  ###################################################
  # Internal methods for building the script data   #
  ###################################################

  # Generates the javascript for initializing each graph/chart
  # @param [String] id the id for the given chart, this should be unique per html page
  # @param [String] chart_type the name of the chart type that we're rendering.
  # @param [DataTable] table the DataTable containing the column definitions and data rows
  # @param [Hash] options the view formatting options
  # @return [String] javascript that creates the chart, and adds it to the window variable
  def generate_visualization(id, chart_type, table, options={})
    # Generate the js chart data
    output = "chartData['#{escape_id(id)}'] = new google.visualization.DataTable();"
    table.columns.each do |col|
      output += "chartData['#{escape_id(id)}'].addColumn('#{escape(table.column_types[col])}', '#{escape(col)}');"
    end
    option_str = parse_options(options)

    output += %Q(
      chartData['#{escape_id(id)}'].addRows(#{table.format_data});
      visualizationCharts['#{escape_id(id)}'] = new google.visualization.#{chart_type.to_s.camelize}(document.getElementById('#{escape_id(id)}'));
      visualizationCharts['#{escape_id(id)}'].draw(chartData['#{escape_id(id)}'], {#{option_str}});
    )
  end

  # Parse options hash into a string containing a javascript hash key-value pairs
  # @param [Hash] options the hash to parse
  # @return [String] a javascript representation of the input
  def parse_options(options)
    options.collect do |key, val|
      str = "#{key}: "
      if val.kind_of? Hash
        str += "{" + parse_options(val) + "}"
      elsif val.kind_of? Array
        str += "[ " + val.collect { |v| "'#{escape(v)}'" }.join(", ") + " ]"
      else
        str += (val.kind_of?(String) ? "'#{escape(val)}'" : val.to_s)
      end
      str
    end.join(',')
  end

  # Convenience method for initializing instance variables
  def init
    @google_visualizations ||= {}
    @visualization_packages ||= []
  end

  # Determines if we're in a debugging environment
  # @return [boolean]
  def debugging?
    debugging = ENV["DEBUG"]
    if defined?(Rails) && Rails.respond_to?(:env)
      debugging = true if ["development", "test"].include? Rails.env
    end
    debugging
  end

  def escape(s)
    if s
      ERB::Util.json_escape(s)
    end
  end

  def escape_id(id)
    if id
      # Let's be extra strict and validate for characters allowed in HTML id attribute.
      # Allow word characters (letters and underscores), digits, dashes, colons and periods.
      id.gsub(/[^\w\d-\:\.]/, "_")
    end
  end

end
