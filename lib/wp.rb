require 'rubygems'
require 'active_record'
require 'xmlrpc/client'
require 'yaml/store'
#require File.dirname(__FILE__) + '/tarpipe.rb'

config = YAML::load(File.open(File.dirname(__FILE__) + "/#{ENV_SET}.yml"))

WP_XMLRPC_URL = config['wordpress_xmlrpc']['url']
WP_XMLRPC_USERNAME = config['wordpress_xmlrpc']['username']
WP_XMLRPC_PASSWORD = config['wordpress_xmlrpc']['password']
WP_DB_HOST = config['wordpress_db']['host']
WP_DB_DATABASE = config['wordpress_db']['database']
WP_DB_USERNAME = config['wordpress_db']['username']
WP_DB_PASSWORD = config['wordpress_db']['password']
WP_DB_SOCKET = config['wordpress_db']['socket']

ActiveRecord::Base.establish_connection(
   :adapter  => "mysql",
   :host     => WP_DB_HOST,
   :username => WP_DB_USERNAME,
   :password => WP_DB_PASSWORD,
   :socket => WP_DB_SOCKET, 
   :database => WP_DB_DATABASE,
   :encoding => "utf8"
 )

ActiveRecord::Base.logger = Logger.new(STDERR)
ActiveRecord::Base.colorize_logging = false

module Wordpress
  
  class Helper
    
    def self.strip_html(str)
      # The messages the bot sends are not HTML and most IM clients create links when they detect the structure
      # So we strip HTML from the posts and let the IM clients work things out by themselves
      str.strip!
      tag_pat = %r,<(?:(?:/?)|(?:\s*)).*?>,
      content = str.gsub(tag_pat, ' ')
      return content
    end
    
    def self.didwhen(old_time) # stolen from http://snippets.dzone.com/posts/show/5715
      val = Time.now - old_time
       if val < 10 then
         result = 'just a moment ago'
       elsif val < 40  then
         result = 'less than ' + (val * 1.5).to_i.to_s.slice(0,1) + '0 seconds ago'
       elsif val < 60 then
         result = 'less than a minute ago'
       elsif val < 60 * 1.3  then
         result = "1 minute ago"
       elsif val < 60 * 50  then
         result = "#{(val / 60).to_i} minutes ago"
       elsif val < 60  * 60  * 1.4 then
         result = 'about 1 hour ago'
       elsif val < 60  * 60 * (24 / 1.02) then
         result = "about #{(val / 60 / 60 * 1.02).to_i} hours ago"
       else
         result = old_time.strftime("%H:%M %p %B %d, %Y")
       end
      return "#{result}"
    end # self.didwhen
    
    
    
  end # Helper
  
  class Persistence
    
    def self.load(id_type)
      status_id = ''
      YAML::Store.new(File.dirname(__FILE__) + '/store/wordpress_store.yml').transaction do |load|
        status_id = load[id_type]
      end
      return status_id
    end # self.store
    
    def self.store(id_type, status_id)
      YAML::Store.new(File.dirname(__FILE__) + '/store/wordpress_store.yml').transaction do |store|
        store[id_type] = status_id
      end
    end # self.store
    
  end # Persistence
  
  class Publish
    
    @wp_xmlrpc_url = WP_XMLRPC_URL
    @wpuser = WP_XMLRPC_USERNAME
    @wppass = WP_XMLRPC_PASSWORD
    
    @server = XMLRPC::Client.new2(@wp_xmlrpc_url)

    def self.post(sender, message)
      desc = message

       wptags = Array.new
       hashtags = desc.scan(/#[09a-zA-Z\-\_\+]+/i)

       hashtags.each do |w|
         b = w.to_s.split(/#/)
         c = b[1].to_s.downcase
         wptags.push c
       end

       # We search for links in the message in order to wrap them in HTML
       # This allows the link to be clickable in the WP blog
       d = URI.extract(desc.to_s, /(http|https)/)
       if d != nil
         d.each do |url|
           url = url.to_s.split(/[^0-9a-zA-Z]+$/i)
           e = "<a href='" + url.to_s + "'>" + url[0].to_s + "</a>"
           f = message.gsub!(url.to_s, e.to_s)
         end
       end

       user = WpUsers.find_user_by_IM_account(sender)
       author_id = user[0]['ID'].to_s

       newPost = {}
       newPost['description'] = desc.to_s
       newPost['title'] = (desc[0..100] + '...').to_s
       newPost['wp_author_id'] = author_id
       newPost['categories'] = ['notes']
       newPost['mt_keywords'] = wptags.join(', ').to_s

      if wptags.include? 'private'
        @server.call('metaWeblog.newPost','unused_blogid',@wpuser,@wppass,newPost,false) #save as draft
      else
        @server.call('metaWeblog.newPost','unused_blogid',@wpuser,@wppass,newPost,true) #publish
      end
      
    end
    
    
    def self.link(sender, message)
      desc = message

       wptags = Array.new
       hashtags = desc.scan(/#[09a-zA-Z\-\_\+]+/i)

       hashtags.each do |w|
         b = w.to_s.split(/#/)
         c = b[1].to_s.downcase
         wptags.push c
       end

       # We search for links in the message in order to wrap them in HTML
       # This allows the link to be clickable in the WP blog
       d = URI.extract(desc.to_s, /(http|https)/)
       if d != nil
         d.each do |url|
           url = url.to_s.split(/[^0-9a-zA-Z]+$/i)
           e = "<a href='" + url.to_s + "'>" + url[0].to_s + "</a>"
           f = message.gsub!(url.to_s, e.to_s)           
         end
       end

       user = WpUsers.find_user_by_IM_account(sender)
       author_id = user[0]['ID'].to_s

       newPost = {}
       newPost['description'] = desc.to_s
       newPost['title'] = (desc[0..100] + '...').to_s
       newPost['wp_author_id'] = author_id
       newPost['categories'] = ['links']
       newPost['mt_keywords'] = wptags.join(', ').to_s

      if wptags.include? 'private'
        @server.call('metaWeblog.newPost','unused_blogid',@wpuser,@wppass,newPost,false) #save as draft
      else
        @server.call('metaWeblog.newPost','unused_blogid',@wpuser,@wppass,newPost,true) #publish
      end
      
    end #self.link method
    
  end #Publish class
  
  class Timeline
    
    def self.live(sender, order)
      
      if @sprint_live_thread and order == 'start'
        targets = Persistence.load('targets')
        if targets.is_a?(Array)
          targets << sender if targets.include?(sender) != true
          refresh_targets = Persistence.store('targets', targets)
        end
      else
        targets = Array.new
        targets.push sender
        store = Persistence.store('targets', targets)
      end # if @sprint_live_thread

      if order == 'start'        
        @sprint_live_thread = Thread.new do 
          Prologuer::Bot.deliver(sender, "Live feed started at #{Time.now.to_s}")
          loop do
            @messages = Array.new
            begin
              if Wordpress::Persistence.load('unread') != nil
                @timeline = Wordpress::WpPosts.find(:all, :conditions => ['ID > ?', Wordpress::Persistence.load('unread')], :order => 'post_date DESC')
              else
                @timeline = Wordpress::WpPosts.find(:all, :order => 'post_date DESC')
              end # if
              rescue
            end # begin
            if @timeline.length > 0
              store = Wordpress::Persistence.store('unread', @timeline.first.ID)
              @timeline.each do |status|
                author = Wordpress::WpUsers.find_by_ID(status.post_author)
                message = author.user_login.to_s + ': ' + Helper.strip_html(status.post_content.to_s) + ' -- ' + Helper.didwhen(status.post_date).to_s
                @messages << message
              end # @timeline.each              
            end # if @timeline.length
            deliverable = Persistence.load('targets')
            deliverable.each do |sender|
              Prologuer::Bot.deliver(sender,@messages)
            end
            sleep 10
          end # loop
        end # Thread.new

      elsif order == 'status'
        if @sprint_live_thread and @sprint_live_thread.alive? != false
          targets = Persistence.load('targets')
            if targets.include?(sender)
              Prologuer::Bot.deliver(sender, 'You are subscribed to the live feed. Try to enjoy the silence.')
            else
              Prologuer::Bot.deliver(sender, 'The live is running but you are not subscribed to it. You can say "live start".')
            end
        else
          Prologuer::Bot.deliver(sender, 'The live stream is not running. Start it by saying "live start"')
        end # if
      elsif order == 'stop'
        targets = Persistence.load('targets')
        if targets.include?(sender)
          targets.delete(sender)
          store_targets = Persistence.store('targets', targets)
          Prologuer::Bot.deliver(sender, 'You are no longer subscribed to the live feed.')
        else 
          Prologuer::Bot.deliver(sender, 'You are not subscribed to the live feed. Nothing happened.')
        end
      end # if

    end # self.live
    
  end # class
  
  
  
  # ActiveRecord Class declarations and some custom SQL
  
  class WpUsers < ActiveRecord::Base

    def self.find_author_by_login(login)
      find(:first, :conditions => ['user_login = ?', login.to_s])
    end

    def self.find_user_by_IM_account(sender)
      find_by_sql("SELECT * FROM wp_users AS u INNER JOIN wp_usermeta AS um ON u.ID = um.user_id WHERE um.meta_key = 'jabber' AND  um.meta_value = '#{sender.to_s}' LIMIT 1")
    end

  end

  class WpPosts < ActiveRecord::Base 

    def self.find_with_scope     
       with_scope(:find => { :conditions => "ORDER BY 'post_date' DESC" }) do
         find(:first)
       end     
    end
  end

  class WpTermTaxonomy < ActiveRecord::Base
    set_table_name "wp_term_taxonomy"  
  end

  class WpTerms < ActiveRecord::Base
  end

  class WpUsermeta < ActiveRecord::Base
    set_table_name "wp_usermeta"
    def self.find_masters
      find_by_sql("SELECT meta_value FROM wp_usermeta WHERE meta_key = 'jabber' AND user_id IN (SELECT user_id FROM wp_usermeta WHERE meta_key = 'wp_user_level')")
    end
  end

  class WpTermRelationships < ActiveRecord::Base

    def self.find_posts_for_tag(id)
      find_by_sql("SELECT tr.object_id FROM wp_term_relationships AS tr INNER JOIN wp_term_taxonomy AS tt ON tr.term_taxonomy_id = tt.term_taxonomy_id WHERE tt.taxonomy = 'post_tag' AND tt.term_id IN (#{id})")
    end

  end


end
