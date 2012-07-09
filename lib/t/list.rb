require 'thor'
require 'twitter'

module T
  autoload :Collectable, 't/collectable'
  autoload :FormatHelpers, 't/format_helpers'
  autoload :Printable, 't/printable'
  autoload :RCFile, 't/rcfile'
  autoload :Requestable, 't/requestable'
  class List < Thor
    include T::Collectable
    include T::Printable
    include T::Requestable
    include T::FormatHelpers

    DEFAULT_NUM_RESULTS = 20
    MAX_USERS_PER_LIST = 500
    MAX_USERS_PER_REQUEST = 100

    check_unknown_options!

    def initialize(*)
      @rcfile = T::RCFile.instance
      super
    end

    desc "add LIST USER [USER...]", "Add members to a list."
    method_option "id", :aliases => "-i", :type => "boolean", :default => false, :desc => "Specify input as Twitter user IDs instead of screen names."
    def add(list, user, *users)
      users.unshift(user)
      require 't/core_ext/string'
      if options['id']
        users.map!(&:to_i)
      else
        users.map!(&:strip_ats)
      end
      require 'retryable'
      retryable(:tries => 3, :on => Twitter::Error::ServerError, :sleep => 0) do
        client.list_add_members(list, users)
      end
      number = users.length
      say "@#{@rcfile.active_profile[0]} added #{number} #{number == 1 ? 'member' : 'members'} to the list \"#{list}\"."
      say
      if options['id']
        say "Run `#{File.basename($0)} list remove --id #{list} #{users.join(' ')}` to undo."
      else
        say "Run `#{File.basename($0)} list remove #{list} #{users.map{|user| "@#{user}"}.join(' ')}` to undo."
      end
    end

    desc "create LIST [DESCRIPTION]", "Create a new list."
    method_option "private", :aliases => "-p", :type => :boolean
    def create(list, description=nil)
      opts = description ? {:description => description} : {}
      opts.merge!(:mode => 'private') if options['private']
      client.list_create(list, opts)
      say "@#{@rcfile.active_profile[0]} created the list \"#{list}\"."
    end

    desc "information [USER/]LIST", "Retrieves detailed information about a Twitter list."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    def information(list)
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
      list = client.list(owner, list)
      if options['csv']
        require 'csv'
        require 'fastercsv' unless Array.new.respond_to?(:to_csv)
        say ["ID", "Description", "Slug", "Screen name", "Created at", "Members", "Subscribers", "Following", "Mode", "URL"].to_csv
        say [list.id, list.description, list.slug, list.user.screen_name, csv_formatted_time(list), list.member_count, list.subscriber_count, list.following?, list.mode, "https://twitter.com#{list.uri}"].to_csv
      else
        array = []
        array << ["ID", list.id.to_s]
        array << ["Description", list.description] unless list.description.nil?
        array << ["Slug", list.slug]
        array << ["Screen name", "@#{list.user.screen_name}"]
        array << ["Created at", "#{ls_formatted_time(list)} (#{time_ago_in_words(list.created_at)} ago)"]
        array << ["Members", number_with_delimiter(list.member_count)]
        array << ["Subscribers", number_with_delimiter(list.subscriber_count)]
        array << ["Status", list.following ? "Following" : "Not following"]
        array << ["Mode", list.mode]
        array << ["URL", "https://twitter.com#{list.uri}"]
        print_table(array)
      end
    end
    map %w(details) => :information

    desc "members [USER/]LIST", "Returns the members of a Twitter list."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "id", :aliases => "-i", :type => "boolean", :default => false, :desc => "Specify user via ID instead of screen name."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    method_option "reverse", :aliases => "-r", :type => :boolean, :default => false, :desc => "Reverse the order of the sort."
    method_option "sort", :aliases => "-s", :type => :string, :enum => %w(favorites followers friends listed screen_name since tweets tweeted), :default => "screen_name", :desc => "Specify the order of the results.", :banner => "ORDER"
    method_option "unsorted", :aliases => "-u", :type => :boolean, :default => false, :desc => "Output is not sorted."
    def members(list)
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
      users = collect_with_cursor do |cursor|
        client.list_members(owner, list, :cursor => cursor, :skip_status => true)
      end
      print_users(users)
    end

    desc "remove LIST USER [USER...]", "Remove members from a list."
    method_option "id", :aliases => "-i", :type => "boolean", :default => false, :desc => "Specify input as Twitter user IDs instead of screen names."
    def remove(list, user, *users)
      users.unshift(user)
      require 't/core_ext/string'
      if options['id']
        users.map!(&:to_i)
      else
        users.map!(&:strip_ats)
      end
      require 'retryable'
      retryable(:tries => 3, :on => Twitter::Error::ServerError, :sleep => 0) do
        client.list_remove_members(list, users)
      end
      number = users.length
      say "@#{@rcfile.active_profile[0]} removed #{number} #{number == 1 ? 'member' : 'members'} from the list \"#{list}\"."
      say
      if options['id']
        say "Run `#{File.basename($0)} list add --id #{list} #{users.join(' ')}` to undo."
      else
        say "Run `#{File.basename($0)} list add #{list} #{users.map{|user| "@#{user}"}.join(' ')}` to undo."
      end
    end

    desc "timeline [USER/]LIST", "Show tweet timeline for members of the specified list."
    method_option "csv", :aliases => "-c", :type => :boolean, :default => false, :desc => "Output in CSV format."
    method_option "id", :aliases => "-i", :type => "boolean", :default => false, :desc => "Specify user via ID instead of screen name."
    method_option "long", :aliases => "-l", :type => :boolean, :default => false, :desc => "Output in long format."
    method_option "number", :aliases => "-n", :type => :numeric, :default => DEFAULT_NUM_RESULTS, :desc => "Limit the number of results."
    method_option "reverse", :aliases => "-r", :type => :boolean, :default => false, :desc => "Reverse the order of the sort."
    def timeline(list)
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
      per_page = options['number'] || DEFAULT_NUM_RESULTS
      statuses = collect_with_per_page(per_page) do |opts|
        client.list_timeline(owner, list, opts)
      end
      print_statuses(statuses)
    end
    map %w(tl) => :timeline

  end
end
