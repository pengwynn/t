require 'thor'
require 'twitter'

module T
  autoload :Collectable, 't/collectable'
  autoload :Printable, 't/printable'
  autoload :RCFile, 't/rcfile'
  autoload :Requestable, 't/requestable'
  class Search < Thor
    include T::Collectable
    include T::Printable
    include T::Requestable

    DEFAULT_NUM_RESULTS = 20
    MAX_NUM_RESULTS = 200

    check_unknown_options!

    def initialize(*)
      @rcfile = T::RCFile.instance
      super
    end

    desc "all QUERY", "Returns the #{DEFAULT_NUM_RESULTS} most recent Tweets that match the specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    method_option "number", :aliases => "-n", :type => :numeric, :default => DEFAULT_NUM_RESULTS
    def all(query)
      rpp = options['number'] || DEFAULT_NUM_RESULTS
      statuses = collect_with_rpp(rpp) do |opts|
        client.search(query, opts).results
      end
      statuses.reverse! if options['reverse']
      require 'htmlentities'
      if options['csv']
        require 'csv'
        require 'fastercsv' unless Array.new.respond_to?(:to_csv)
        say STATUS_HEADINGS.to_csv unless statuses.empty?
        statuses.each do |status|
          say [status.id, csv_formatted_time(status), status.from_user, HTMLEntities.new.decode(status.full_text)].to_csv
        end
      elsif options['long']
        array = statuses.map do |status|
          [status.id, ls_formatted_time(status), "@#{status.from_user}", HTMLEntities.new.decode(status.full_text).gsub(/\n+/, ' ')]
        end
        format = options['format'] || STATUS_HEADINGS.size.times.map{"%s"}
        print_table_with_headings(array, STATUS_HEADINGS, format)
      else
        say unless statuses.empty?
        statuses.each do |status|
          print_message(status.from_user, status.full_text)
        end
      end
    end

    desc "favorites QUERY", "Returns Tweets you've favorited that match the specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    def favorites(query)
      opts = {:count => MAX_NUM_RESULTS}
      statuses = collect_with_max_id do |max_id|
        opts[:max_id] = max_id unless max_id.nil?
        client.favorites(opts)
      end
      statuses = statuses.select do |status|
        /#{query}/i.match(status.full_text)
      end
      print_statuses(statuses)
    end
    map %w(faves) => :favorites

    desc "list [USER/]LIST QUERY", "Returns Tweets on a list that match specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "id", :aliases => "-i", :type => "boolean", :default => false, :desc => "Specify user via ID instead of screen name."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    def list(list, query)
      owner, list = list.split('/')
      if list.nil?
        list = owner
        owner = @rcfile.active_profile[0]
      else
        require 't/core_ext/string'
        owner = if options['id']
          owner.to_i
        else
          owner.strip_ats
        end
      end
      opts = {:count => MAX_NUM_RESULTS}
      statuses = collect_with_max_id do |max_id|
        opts[:max_id] = max_id unless max_id.nil?
        client.list_timeline(owner, list, opts)
      end
      statuses = statuses.select do |status|
        /#{query}/i.match(status.full_text)
      end
      print_statuses(statuses)
    end

    desc "mentions QUERY", "Returns Tweets mentioning you that match the specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    def mentions(query)
      opts = {:count => MAX_NUM_RESULTS}
      statuses = collect_with_max_id do |max_id|
        opts[:max_id] = max_id unless max_id.nil?
        client.mentions(opts)
      end
      statuses = statuses.select do |status|
        /#{query}/i.match(status.full_text)
      end
      print_statuses(statuses)
    end
    map %w(replies) => :mentions

    desc "retweets QUERY", "Returns Tweets you've retweeted that match the specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    def retweets(query)
      opts = {:count => MAX_NUM_RESULTS}
      statuses = collect_with_max_id do |max_id|
        opts[:max_id] = max_id unless max_id.nil?
        client.retweeted_by(opts)
      end
      statuses = statuses.select do |status|
        /#{query}/i.match(status.full_text)
      end
      print_statuses(statuses)
    end
    map %w(rts) => :retweets

    desc "timeline [USER] QUERY", "Returns Tweets in your timeline that match the specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "id", :aliases => "-i", :type => "boolean", :default => false, :desc => "Specify user via ID instead of screen name."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    def timeline(*args)
      opts = {:count => MAX_NUM_RESULTS}
      query = args.pop
      user = args.pop
      if user
        require 't/core_ext/string'
        user = if options['id']
          user.to_i
        else
          user.strip_ats
        end
        statuses = collect_with_max_id do |max_id|
          opts[:max_id] = max_id unless max_id.nil?
          client.user_timeline(user, opts)
        end
      else
        statuses = collect_with_max_id do |max_id|
          opts[:max_id] = max_id unless max_id.nil?
          client.home_timeline(opts)
        end
      end
      statuses = statuses.select do |status|
        /#{query}/i.match(status.full_text)
      end
      print_statuses(statuses)
    end
    map %w(tl) => :timeline

    desc "users QUERY", "Returns users that match the specified query."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    method_option "reverse", :aliases => "-r", :type => :boolean, :default => false, :desc => "Reverse the order of the sort."
    method_option "sort", :aliases => "-s", :type => :string, :enum => %w(favorites followers friends listed screen_name since tweets tweeted), :default => "screen_name", :desc => "Specify the order of the results.", :banner => "ORDER"
    method_option "unsorted", :aliases => "-u", :type => :boolean, :default => false, :desc => "Output is not sorted."
    def users(query)
      users = collect_with_page do |page|
        client.user_search(query, :page => page)
      end
      print_users(users)
    end

  end
end
