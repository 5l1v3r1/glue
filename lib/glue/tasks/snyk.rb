require 'glue/tasks/base_task'
require 'glue/util'
require 'redcarpet'

class Glue::Snyk < Glue::BaseTask

  Glue::Tasks.add self
  include Glue::Util

  def initialize(trigger, tracker)
    super(trigger, tracker)
    @name = "Snyk"
    @description = "Snyk.io JS dependency checker"
    @stage = :code
    @labels << "code" << "javascript"
    @results = []
  end

  def run
    exclude_dirs = ['node_modules','bower_components']
    exclude_dirs = exclude_dirs.concat(@tracker.options[:exclude_dirs]).uniq if @tracker.options[:exclude_dirs]
    directories_with?('package.json', exclude_dirs).each do |dir|
      Glue.notify "#{@name} scanning: #{dir}"
      @results << JSON.parse(runsystem(true, "snyk", "test", "--json", :chdir => dir))["vulnerabilities"]
    end
  end

  def analyze
    markdown = Redcarpet::Markdown.new Redcarpet::Render::HTML.new(link_attributes: {target: "_blank"}), autolink: true, tables: true

    @results.each do |dir_result|
      # We build a single finding for each uniq result ID, adding the unique info (upgrade path and files) as a list
      dir_result.uniq {|r| r['id']}.each do |result|
        description = "#{result['name']}@#{result['version']} - #{result['title']}"

        # Use Redcarpet to render the Markdown details to something pretty for web display
        detail = markdown.render(result['description']).gsub('h2>','strong>').gsub('h3>', 'strong>')
        upgrade_paths = [ "Upgrade Path:\n" ]
        files = []

        # Pull the list of files and upgrade paths from all results matching this ID
        # This uses the same form as the retirejs task so it all looks nice together
        dir_result.select{|r| r['id'] == result['id']}.each do |res|
          res['upgradePath'].each_with_index do |upgrade, i|
            upgrade_paths << "#{res['from'][i]} -> #{upgrade}"
          end
          files << res['from'].join('->')
        end

        source = {
          :scanner => @name,
          :file => files.join('<br>'),
          :line => nil,
          :code => upgrade_paths.uniq.join("\n"),
        }
        sev = severity(result['severity'])
        fprint = fingerprint("#{description}#{detail}#{source}#{sev}")

        report description, detail, source, sev, fprint
      end
    end
  end

  def supported?
    supported = find_executable0('snyk')
    unless supported
      Glue.notify "Install Snyk: 'npm install -g snyk'"
      return false
    else
      return true
    end
  end

end
