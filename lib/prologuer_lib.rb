require 'rubygems'
require 'jabber/bot'


require File.dirname(__FILE__) + '/wp.rb'

 # Load specified configuration file
  
config = YAML::load(File.open(File.dirname(__FILE__) + "/#{ENV_SET}.yml"))

JABBER_USERNAME = config['jabber']['username']
JABBER_PASSWORD = config['jabber']['password']


module Prologuer

class Bot
  
  def initialize
    masters = Array.new
    Wordpress::WpUsermeta.find_masters.each do |master|
      masters.push master['meta_value']
    end
        

    @@bot = Jabber::Bot.new(
      :jabber_id => JABBER_USERNAME, 
      :password  => JABBER_PASSWORD, 
      :master    => masters,
      :is_public => true
    )
    
    load_commands
    
    @@bot.connect
    
  end
  
  def self.deliver(sender, message)
    if message.is_a?(Array)
      message.each { |message| @@bot.deliver(sender, message)}
    else
      @@bot.deliver(sender, message)
    end
  end

  def deliver(sender, message)
    if message.is_a?(Array)
      message.each { |message| @@bot.deliver(sender, message)}
    else
      @@bot.deliver(sender, message)
    end
  end


  def load_commands
    
     @@bot.add_command(
        :syntax      => 'link http://yourlink.com #tags',
        :description => 'Post a link',
        :regex       => /^link\s+.+$/,
        :is_public   => false
      ) do |sender, message|
          execute_link_command(sender, message)
        nil
      end
      
      @@bot.add_command(
         :syntax      => 'live start|stop|status',
         :description => 'Start the live feed',
         :regex       => /^(live|Live)\s+.+$/,
         :is_public   => false
       ) do |sender, message|
           execute_live_command(sender, message)
         nil
       end  

    #The post command posts a message to WordPress; it can handle #hashtags that WP will store as tags (cf. Wordpress::Publish.post) 
    @@bot.add_command(
      :syntax      => 'post Your message',
      :description => 'Post something to your Prologue install. You can post #hashtags; using the #private hashtag will post your message as a draft.',
      :regex       => /^(post|Post)\s+.+$/,
      :is_public   => false
    ) do |sender, message|
       execute_post_command(sender, message)
      nil
    end
    
    #The last command will output the latest 'n' messages posted on the blog
    @@bot.add_command(
      :syntax      => 'last "n"',
      :description => 'Query the timeline for the last "n" messages, where "n" is a number',
      :regex       => /^last\s+.+$/,
      :is_public   => false
    ) do |sender, message|
        execute_last_command(sender, message)
      nil
    end
    
    #the q command will output all messages posted by given authors and with given tags
    @@bot.add_command(
      :syntax      => 'q #tag @person',
      :description => 'Query the timeline for content published by @person and/or #hashtag (can be more than 1)',
      :regex       => /^(q|Q)\s+.+$/,
      :is_public   => false
    ) do |sender, message|
        execute_q_command(sender,message)
      nil
    end
    
  end
  
  def execute_post_command(sender,message)
    post = Wordpress::Publish.post(sender, message)
    deliver(sender, 'Ooops, your message was not posted') unless post
  end
  
  def execute_link_command(sender,message)
    Wordpress::Publish.link(sender, message)
    deliver(sender, 'OK, your link was posted')
  end # execute_link_command
  
  def execute_live_command(sender, message)
    Wordpress::Timeline.live(sender, message)
  end # execute_live_command
  
  def execute_last_command(sender, message)
    
    if message =~ /[0-9]/
      messages = Array.new
      posts = Wordpress::WpPosts.find(:all, :limit => message, :order => "post_date DESC", :conditions => "post_status = 'publish'")
      posts.each do |post|
        user = Wordpress::WpUsers.find_by_ID(post.post_author)
        #strip_html(post.post_content.to_s) #returns @content
        #messages.push((user.display_name.to_s + ": " + @content.to_s).to_s)
        messages.push(prepare_for_delivery(user.user_login, post.post_content.to_s, post.post_date))
      end
      deliver(sender, messages)
    else
      deliver(sender, 'An error occurred, please type HELP and review the options.')
    end
     
  end
  
  def execute_q_command(sender, message)
    
    #determine if and what authors are requested
    authors = Array.new
    authors = message.scan(/@[a-zA-Z0-9]+/i)
    if authors.length != 0
      @authors = true
    elsif authors.length == 0
      @authors = false
    end
      
    #determine if and what tags are requested
    hashtags = Array.new
    hashtags = message.scan(/#[a-zA-Z0-9\-\_\+]+/i)
    if hashtags.length != 0
      @tags = true
    elsif hashtags.length == 0
      @tags = false
    end    
    
    #a set of instance variables that will help
    @tag_ids = Array.new
    @posts_by_tag = Array.new
    @authors_ids = Array.new
    #this instance variable accumulates errors in order to deliver a precise error message 
    @wrong_query = Array.new
    
    #if authors are requested, lookup their WP ids; if at least one request author is not found, abort
    if @authors == true
      authors.each do |w|
        b = w.to_s.split(/@/)
        c = b[1].to_s.downcase
        author = Wordpress::WpUsers.find_author_by_login(c)
        if author != nil 
          author_id = author.ID
          @authors_ids.push author_id
        elsif author == nil
          @wrong_query.push w
          @authors = false
        end
      end
    end
    
    #if tags are requested, lookup their WP ids; if at least one requested tag is not found, abort
    if @tags == true
      hashtags.each do |w|
        b = w.to_s.split(/#/)
        c = b[1].to_s.downcase
        tag = Wordpress::WpTerms.find(:first, :conditions => ['name = ?', c])
        if tag != nil
          tag_id = tag.term_id
          @tag_ids.push tag_id
        elsif tag == nil
          @wrong_query.push w 
          @tags = false
          @authors = false
        end
        end
      end
      
      #if we have tags, lookup posts that correspond
      @tag_ids.each do |w| unless @tags != true
        posts_for_tag = Wordpress::WpTermRelationships.find_posts_for_tag(w)
        if posts_for_tag != nil
          posts_for_tag.each do |post|
            p_id = post['object_id']
            @posts_by_tag.push p_id
          end
        elsif posts_for_tag == nil
          @tags = false
          @authors = false
        end
      end
    end

    #finally, lookup the 5 latest relevant posts, format and send to delivery
        if @tags == true and @authors != true 
          messages = Array.new
          @posts = Wordpress::WpPosts.find(:all, :conditions => ['ID in (?) AND post_status = "publish"', @posts_by_tag.uniq], :order => "post_date DESC", :limit => 5)
          @posts.each do |post|
            user = Wordpress::WpUsers.find_by_ID(post.post_author)
            #strip_html(post.post_content.to_s)
            #messages.push((user.user_login + ': ' + @content).to_s)
            messages.push(prepare_for_delivery(user.user_login, post.post_content, post.post_date))
          end
          deliver(sender, messages)
        elsif @authors == true and @tags != true
          messages = Array.new
          @posts = Wordpress::WpPosts.find(:all, :conditions => ['post_author in (?) AND post_status = "publish"', @authors_ids], :order => "post_date DESC", :limit => 5)          
          @posts.each do |post|
            user = Wordpress::WpUsers.find_by_ID(post.post_author)
            #strip_html(post.post_content.to_s) #returns @content
            #messages.push((user.user_login + ': ' + @content).to_s)
            messages.push(prepare_for_delivery(user.user_login, post.post_content.to_s, post.post_date))
          end
          deliver(sender, messages)
        elsif @tags == true and @authors == true
          messages = Array.new
          @posts = Wordpress::WpPosts.find(:all, :conditions => ['post_author in (?) AND ID in (?) AND post_status = "publish"', @authors_ids, @posts_by_tag.uniq], :order => "post_date DESC", :limit => 3)
          @posts.each do |post|
            user = Wordpress::WpUsers.find_by_ID(post.post_author)
            #strip_html(post.post_content.to_s) #returns @content
            #messages.push((user.user_login + ': ' + @content).to_s)
            messages.push(prepare_for_delivery(user.user_login, post.post_content.to_s, post.post_date))
          end
          deliver(sender, messages)
        elsif @tags != true and @authors != true and @wrong_query.length != 0
          if @wrong_query.length > 1
            @wrong_query = @wrong_query.join("' nor '")
          else
            @wrong_query = @wrong_query.each{|x| print x }
          end
          message = "Sorry, I couldn't find any information regarding '" +  @wrong_query.to_s + "', so I aborted. Please, double-check your request."
          deliver(sender, message)
        else
          message = "Sorry, but I don't know what you're looking for. Please type 'help q' to understand how to use this command."
          deliver(sender,message)
        end
    #ok, the execution is done, method ends here
  end
  
  
  
  # this method is a helper
  def prepare_for_delivery(author, content, pubdate)
    author.to_s + ': ' + strip_html(content).to_s + ' -- ' + didwhen(pubdate).to_s
  end
  
  
  #this method is a helper
  def strip_html(str)
    # The messages the bot sends are not HTML and most IM clients create links when they detect the structure
    # So we strip HTML from the posts and let the IM clients work things out by themselves
    str.strip!
    tag_pat = %r,<(?:(?:/?)|(?:\s*)).*?>,
    return str.gsub(tag_pat, ' ')
  end
  
  
  # this method is a helper
  def didwhen(old_time) # stolen from http://snippets.dzone.com/posts/show/5715
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
    
end #ends Bot class

end #ends Prologuer module

Prologuer::Bot.new
