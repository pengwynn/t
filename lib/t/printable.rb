module T
  module Printable
    LIST_HEADINGS = ["ID", "Created at", "Screen name", "Slug", "Members", "Subscribers", "Mode", "Description"]
    STATUS_HEADINGS = ["ID", "Posted at", "Screen name", "Text"]
    USER_HEADINGS = ["ID", "Since", "Last tweeted at", "Tweets", "Favorites", "Listed", "Following", "Followers", "Screen name", "Name"]
    MONTH_IN_SECONDS = 2592000

  private

    def build_long_list(list)
      [list.id, ls_formatted_time(list), "@#{list.user.screen_name}", list.slug, list.member_count, list.subscriber_count, list.mode, list.description]
    end

    def build_long_status(status)
      require 'htmlentities'
      [status.id, ls_formatted_time(status), "@#{status.from_user}", HTMLEntities.new.decode(status.full_text).gsub(/\n+/, ' ')]
    end

    def build_long_user(user)
      [user.id, ls_formatted_time(user), ls_formatted_time(user.status), user.statuses_count, user.favourites_count, user.listed_count, user.friends_count, user.followers_count, "@#{user.screen_name}", user.name]
    end

    def csv_formatted_time(object, key=:created_at)
      return nil if object.nil?
      time = object.send(key.to_sym)
      time.utc.strftime("%Y-%m-%d %H:%M:%S %z")
    end

    def ls_formatted_time(object, key=:created_at)
      return "" if object.nil?
      time = T.local_time(object.send(key.to_sym))
      if time > Time.now - MONTH_IN_SECONDS * 6
        time.strftime("%b %e %H:%M")
      else
        time.strftime("%b %e  %Y")
      end
    end

    def print_csv_list(list)
      require 'csv'
      require 'fastercsv' unless Array.new.respond_to?(:to_csv)
      say [list.id, csv_formatted_time(list), list.user.screen_name, list.slug, list.member_count, list.subscriber_count, list.mode, list.description].to_csv
    end

    def print_csv_status(status)
      require 'csv'
      require 'fastercsv' unless Array.new.respond_to?(:to_csv)
      require 'htmlentities'
      say [status.id, csv_formatted_time(status), status.from_user, HTMLEntities.new.decode(status.full_text)].to_csv
    end

    def print_csv_user(user)
      require 'csv'
      require 'fastercsv' unless Array.new.respond_to?(:to_csv)
      say [user.id, csv_formatted_time(user), csv_formatted_time(user.status), user.statuses_count, user.favourites_count, user.listed_count, user.friends_count, user.followers_count, user.screen_name, user.name].to_csv
    end

    def print_lists(lists)
      lists = lists.sort_by{|list| list.slug.downcase} unless options['unsorted']
      if options['posted']
        lists = lists.sort_by{|user| user.created_at}
      elsif options['members']
        lists = lists.sort_by{|user| user.member_count}
      elsif options['mode']
        lists = lists.sort_by{|user| user.mode}
      elsif options['subscribers']
        lists = lists.sort_by{|user| user.subscriber_count}
      end
      lists.reverse! if options['reverse']
      if options['csv']
        require 'csv'
        require 'fastercsv' unless Array.new.respond_to?(:to_csv)
        say LIST_HEADINGS.to_csv unless lists.empty?
        lists.each do |list|
          print_csv_list(list)
        end
      elsif options['long']
        array = lists.map do |list|
          build_long_list(list)
        end
        format = options['format'] || LIST_HEADINGS.size.times.map{"%s"}
        print_table_with_headings(array, LIST_HEADINGS, format)
      else
        print_attribute(lists, :full_name)
      end
    end

    def print_attribute(array, attribute)
      if STDOUT.tty?
        print_in_columns(array.map(&attribute.to_sym))
      else
        array.each do |element|
          say element.send(attribute.to_sym)
        end
      end
    end

    def print_table_with_headings(array, headings, format)
      return if array.flatten.empty?
      if STDOUT.tty?
        array.unshift(headings)
        require 't/core_ext/kernel'
        array.map! do |row|
          row.each_with_index.map do |element, index|
            Kernel.send(element.class.name.to_sym, format[index] % element)
          end
        end
        print_table(array, :truncate => true)
      else
        print_table(array)
      end
    end

    def print_message(from_user, message)
      if STDOUT.tty? && !options['no-color']
        say("   @#{from_user}", [:bold, :yellow])
      else
        say("   @#{from_user}")
      end
      require 'htmlentities'
      print_wrapped(HTMLEntities.new.decode(message), :indent => 3)
      say
    end

    def print_statuses(statuses)
      statuses.reverse! if options['reverse']
      if options['csv']
        require 'csv'
        require 'fastercsv' unless Array.new.respond_to?(:to_csv)
        say STATUS_HEADINGS.to_csv unless statuses.empty?
        statuses.each do |status|
          print_csv_status(status)
        end
      elsif options['long']
        array = statuses.map do |status|
          build_long_status(status)
        end
        format = options['format'] || STATUS_HEADINGS.size.times.map{"%s"}
        print_table_with_headings(array, STATUS_HEADINGS, format)
      else
        statuses.each do |status|
          print_message(status.user.screen_name, status.full_text)
        end
      end
    end

    def print_users(users)
      users = users.sort_by{|user| user.screen_name.downcase} unless options['unsorted']
      if options['posted']
        users = users.sort_by{|user| user.created_at}
      elsif options['favorites']
        users = users.sort_by{|user| user.favourites_count}
      elsif options['followers']
        users = users.sort_by{|user| user.followers_count}
      elsif options['friends']
        users = users.sort_by{|user| user.friends_count}
      elsif options['listed']
        users = users.sort_by{|user| user.listed_count}
      elsif options['tweets']
        users = users.sort_by{|user| user.statuses_count}
      elsif options['tweeted']
        users = users.sort_by{|user| user.status.created_at rescue Time.at(0)}
      end
      users.reverse! if options['reverse']
      if options['csv']
        require 'csv'
        require 'fastercsv' unless Array.new.respond_to?(:to_csv)
        say USER_HEADINGS.to_csv unless users.empty?
        users.each do |user|
          print_csv_user(user)
        end
      elsif options['long']
        array = users.map do |user|
          build_long_user(user)
        end
        format = options['format'] || USER_HEADINGS.size.times.map{"%s"}
        print_table_with_headings(array, USER_HEADINGS, format)
      else
        print_attribute(users, :screen_name)
      end
    end

  end
end
