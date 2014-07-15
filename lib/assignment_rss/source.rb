require 'open-uri'
require 'simple-rss'
module AssignmentRss
  class Source
    attr_accessor :url, :max_age, :feed_class, :entry_class
    def initialize(url, max_age, feed_class, entry_class, mapping = {})
      @url = url
      @max_age = max_age
      @feed_class = feed_class
      @entry_class = entry_class
      @mapping = mapping
      rss_feed_entries = mapping[:rss_feed_entries] || {}
      @mapping[:rss_feed_entries] = rss_feed_entries
      @feed = feed_class.where(url: @url).first_or_create
    end

    def cached
      return false if time_to_expired == 0
      true
    end

    def time_to_expired
      return 0 if rss_updated.blank?
      left = Time.now - (rss_updated + max_age)
      left > 0 ? 0 : left
    end

    def get_feed
      if cached
        self
      else
        rebuild_mapping
        self
      end
    end

    def rss_feed_entries
      return @feed.rss_feed_entries.to_a if cached && @feed.rss_feed_entries.present?
      rebuild_rss_feed_items_mapping
      @feed.rss_feed_entries.reload
      @feed.rss_feed_entries.to_a
    end

    def mapping(mapping = {})
      return @mapping.merge!(mapping) if mapping.present?
      @mapping
    end

    def rebuild_mapping
      rebuild_rss_feed_mapping && rebuild_rss_feed_items_mapping
    end

    def rebuild_rss_feed_mapping
      @mapping[:title].present? ? title = simple_rss.channel.send(@mapping[:title]) : title = simple_rss.title
      attributes = {
        url: @url,
        title: title,
        link: @url,
        rss_updated: rss_updated,
        updated_at: Time.now
      }
      @feed.update_attributes(attributes)
    end

    def rebuild_rss_feed_items_mapping
      simple_rss.items.each do |entry|
        guid = mapping[:rss_feed_entries][:guid].present? ? entry[mapping[:rss_feed_entries][:guid]] : entry[:guid]
        title = mapping[:rss_feed_entries][:title].present? ? entry[mapping[:rss_feed_entries][:title]] : entry[:title] || ''
        author = mapping[:rss_feed_entries][:author].present? ? entry[mapping[:rss_feed_entries][:author]] : entry[:author] || ''
        link = mapping[:rss_feed_entries][:link].present? ? entry[mapping[:rss_feed_entries][:link]] : entry[:link] || ''
        content = mapping[:rss_feed_entries][:content].present? ? entry[mapping[:rss_feed_entries][:content]] : entry[:content] || ''
        attributes = {
          entry_id: guid,
          title: title.force_encoding('utf-8'),
          author: author.force_encoding('utf-8'),
          link: link,
          content: content.force_encoding('utf-8'),
          rss_feed_id: @feed.id
        }
        if guid.present?
          rss_entry = entry_class.where(entry_id: guid).first_or_initialize
        else
          rss_entry = entry_class.where(link: link).first_or_initialize
        end
        attributes.merge!(rss_updated: rss_updated) if !rss_updated || rss_updated > (rss_entry.rss_updated || Time.new(0))
        rss_entry.update_attributes(attributes)
        rss_entry
      end
    end

    def method_missing(method_name, *args, &block)
      @feed.send(method_name, *args, &block)
    end

    def response_to_missing?(method_name, include_private=false)
      @feed.send(method_name, include_private) || super
    end

    private

      def simple_rss
        if cached && @simple_rss
          @simple_rss
        else
          self.rss_updated = Time.now
          @simple_rss = SimpleRSS.parse(open(@url))
          @simple_rss
        end
      end
  end
end
