require "rubygems"
require "sinatra/base"
require "haml"
require "sass"
require "grit"
require "rdiscount"
require "cgi"

def project_specific_css
  if (git_obj = GitWiki.tree/'project.css')
    git_obj.data
  end
end

module GitWiki
  class << self
    attr_accessor :homepage, :extension, :repository_folder, :subfolder
    attr_accessor :upstream_server_online
    attr_accessor :messages
  end

  # Creates a new instance of a Wiki application. Run with
  # `run GitWiki.new(<params>)`
  #
  # @param [String] repository_folder Folder of the git repository
  # @param [String] extension `.markdown` is recommended
  # @param [String] homepage The name of the default wiki page, e.g. `Home`
  # @param [Optional String] subfolder
  #     You can use git-wiki for documentation of your software project. Simply
  #     put all the content in markdown format into a subfolder, e.g. `wiki` and
  #     provide the folder name as optional parameter.
  def self.new(repository_folder, extension, homepage, subfolder = nil)
    self.homepage   = homepage
    self.extension  = extension
    self.repository_folder = repository_folder
    self.subfolder = subfolder
    self.messages = []
    puts "Initialized wiki with repository at #{repository_folder}"

    App
  end

  def self.add_message(msg)
    messages << msg
    puts msg
  end

  def self.repository
    @repo ||= Grit::Repo.new(self.repository_folder)
  end

  def self.upstream_configured?
    Dir.chdir(GitWiki.repository.working_dir) do
      return self.repository.git.list_remotes.include?('origin')
    end
  end

  # @return Output of the rebase command
  def self.refresh!
    res = ""
    Dir.chdir(GitWiki.repository.working_dir) do
      if upstream_configured?
        res =  "$ git pull --rebase\n"
        res += `date --rfc-3339=seconds;git pull --rebase;date --rfc-3339=seconds`
        self.upstream_server_online = ($? == 0)
      else
        self.upstream_server_online = false
      end
    end
    add_message res
    res
  end

  def self.commit(commit_message)
    Dir.chdir(GitWiki.repository.working_dir) do
      repository.commit_index(commit_message)

      if self.upstream_server_online
        Dir.chdir(GitWiki.repository.working_dir) do
          res = `git push`
          if $?.exitstatus != 0
            add_message "git push failed!\n#{res}"
          else
            add_message "git push successful!\n#{res}"
          end
        end
      else
        add_message "Upstream server unavailable! Saving only locally."
      end
    end
  end

  # return true if the content is empty and the topic has been deleted
  def self.delete_if_empty(page, new_content)
    Dir.chdir(GitWiki.repository.working_dir) do
      if new_content.strip.empty?
        GitWiki.repository.remove(page.rel_file_name)
        GitWiki.commit("Wiki: deleted #{page.name}")
        return true
      end
    end
    false
  end

  def self.update_content(page, new_content)
    new_content.gsub!("\r", "")
    return if new_content == page.content
    Dir.chdir(GitWiki.repository.working_dir) do
      File.open(page.rel_file_name, "w") { |f| f << new_content }
      GitWiki.repository.add(page.rel_file_name)
      GitWiki.commit(page.commit_message)
    end
  end

  def self.tree
    res = self.repository.tree
    self.subfolder ? res / self.subfolder : res
  end

  class PageNotFound < Sinatra::NotFound
    attr_reader :name

    def initialize(name)
      @name = name
    end
  end

  class Task
    attr_accessor :orig_string, :start, :orig_attributes_str, :attributes, :desc, :origin

    TAGGED_VALUE_REGEX = /(\w+)\:(\w+)\s+/

    def self.parse(from_string)
      t = Task.new
      t.orig_string = from_string + ' ' # add space to parse include statements without description
      return nil unless t.orig_string =~
        /^(?: \s*\*?\s*)                  # allow leading * with white space to both sides
        ((?: DO|TODO|DONE|CANCEL|INCLUDE):?\s+)  # 1:TODO with optional colon
        (#{TAGGED_VALUE_REGEX}+)?         # tagged values 2:, 3:, 4:
        (.*)                              # 5:title
        /x
      t.start = $1
      t.orig_attributes_str = $2
      t.desc = $+.strip

      t.attributes = []
      t.attributes = $2.scan(TAGGED_VALUE_REGEX) if $2

      t
    end

    def inner_html
      attr_str = attributes.map{|key, value| "#{key}:#{value} "}.join
      desc_in_html = RDiscount.new(desc).to_html
      html = "<span style='font-weight:bold'>#{start}</span>#{attr_str}#{desc_in_html}"
      html = "<del>#{html}</del>" if done?
      html
    end

    def wrap_div(inner)
      "<div class='todo'>#{inner}</div>\n"
    end

    def to_html
      wrap_div(inner_html)
    end

    def done?
      start =~ /DONE|CANCEL/
    end

    def include_statement?
      start =~ /INCLUDE/
    end

    def [](key)
      hit = attributes.detect {|k, value| k.to_s == key.to_s}
      hit ? hit[1] : nil
    end

    def project
      self[:project]
    end

    def context
      self[:context]
    end
  end

  Origin = Struct.new(:name, :view_url, :edit_url, :attributes) # referencing (parent) page

  # List of todo tasks
  class TaskList
    attr_accessor :example, :tasks

    def initialize
      self.tasks = []
    end

    # @example [Task] contains attributes for task filtering ("filter by example"),
    #                 also defines the source of the tasks (Wiki-Name or url)
    # @recursive_origins [string Array] nil for no recursion or an array of already
    #                              visited nodes; needed to avoid endless recursion
    def self.from_example(example, recursive_origins = nil)
      res = TaskList.new
      res.example = example
      merge_attributes = {}
      merge_attributes[:project] = example.project if example.project
      merge_attributes[:context] = example.context if example.context

      if example[:wiki] == 'all' # load all tasks from all wiki pages
        Page.find_all.each {|p| puts "loading #{p.name}"; res.fill_from_git p.name, merge_attributes, recursive_origins}
      elsif example.desc =~ /^http/ # load by url
        res.fill_from_url(example.desc, merge_attributes) rescue res.example.desc "CAN NOT RETRIEVE URL"
      else # load from one wiki page
        wiki_name = "Project#{example.project}" if example.project
        wiki_name = "Context#{example.context}" if example.context
        wiki_name = example[:wiki] if example[:wiki]
        if wiki_name
          begin
            res.fill_from_git wiki_name, merge_attributes, recursive_origins
          rescue PageNotFound => p
            res.example.desc = "PAGE NOT FOUND #{p.name}"
          end
        end
      end
      res
    end

    def self.derive_attributes_from_page_name(name)
      res = {}
      res[:project] = $1 if name =~ /Project(\w+)/
      res[:context] = $1 if name =~ /Context(\w+)/
      res
    end

    def fill_from_git(page, merge_attributes = {}, recursive_origins = nil)
      if p = Page.find(page)
        attrs = TaskList.derive_attributes_from_page_name(p.name)
        o = Origin.new(page, "/#{page}", "/#{page}/edit", attrs.merge(merge_attributes))
        fill_from_string(p.content, attrs, o, recursive_origins)
      end
    end

    def fill_from_url(url, merge_attributes = {})
      require 'rest_client'
      content = RestClient.get(url) rescue 'Content could not be retrieved.'
      o = Origin.new(url, url, nil)
      fill_from_string(content, merge_attributes, o)
    end

    def fill_from_string(content, merge_attributes, origin, recursive_origins = nil)
      # avoid endless recursion
      if recursive_origins && recursive_origins.detect?{|o| o.name == origin.name}
        puts "Breaking endless recursion #{recursive_origins.inspect}"
        return
      end
      recursive_origins << origin if recursive_origins

      content.each_line do |line|
        task = Task.parse(line) # try every line as a task decription
        if !task.nil?
          merge_attributes.each do |key, value|
            task.attributes << [key, value] unless task[key]
          end
          task.origin = origin.edit_url || origin.view_url
          if task.include_statement? && recursive_origins
            list = TaskList.from_example(task, recursive_origins)
            self.tasks = self.tasks + list.tasks
          else
            tasks << task
          end
        end
      end
    end

    def filter(example)
    end

    def to_html
      tasks_html = tasks.map do |task|
        link = " (<a href='#{task.origin}'>edit</a>)"
        task.wrap_div(task.inner_html + link)
      end
      "<div class='included'>
         <h2>#{example.to_html} (#{tasks.size} tasks)</h2>
         #{tasks_html.join("\n")}
       </div>"
    end
  end

  class Page
    def self.find_all
      return [] if GitWiki.tree.contents.empty?
      GitWiki.tree.contents.
        select {|blob| File.extname(blob.name) == GitWiki.extension }.
        collect {|blob| new(blob)}.
        sort_by {|page| page.name.downcase}
    end

    def self.find(name)
      page_blob = GitWiki.tree/(name + extension)
      raise PageNotFound.new(name) unless page_blob
      new(page_blob)
    end

    def self.search(name)
      return [] if GitWiki.tree.contents.empty?
      GitWiki.tree.contents.
        select {|blob| File.extname(blob.name) == GitWiki.extension }.
        select {|blob| blob.name.downcase.index(name.downcase) }.
        collect {|blob| new(blob)}.
        sort_by {|page| page.name.downcase}
    end

    def self.find_or_create(name)
      find(name)
    rescue PageNotFound
      new(Grit::Blob.create(GitWiki.repository, {
        :name => name + extension,
        :data => ""
      }))
    end

    def self.css_class_for(name)
      find(name)
      "exists"
    rescue PageNotFound
      "unknown"
    end

    def self.extension
      GitWiki.extension || raise
    end

    attr_accessor :content

    def initialize(blob)
      @blob = blob
      @content = blob.data
    end

    def last_changed
      res = nil
      Dir.chdir(GitWiki.repository.working_dir) do
        file_path = GitWiki.subfolder ? File.join(GitWiki.subfolder, @blob.name) : @blob.name
        res = `git log -1 --pretty=format:'%ci' #{file_path}`
      end
      res
    end

    def last_change_hash
      res = nil
      Dir.chdir(GitWiki.repository.working_dir) do
        file_path = GitWiki.subfolder ? File.join(GitWiki.subfolder, @blob.name) : @blob.name
        res = `git log -1 --pretty=format:'%H' #{file_path}`
      end
      res
    end

    def to_html
      html = RDiscount.new(inject_todo(inject_subtopics(content))).to_html
      html = inject_links(inject_sections(inject_header(html)))
      html
    end

    def inject_header(orig)
      orig =~ /<h1>/ ? orig : "<h1>#{name}</h1>" + orig
    end

    def inject_sections(orig, level=1)
      return unless orig
      sections = orig.split("<h#{level}")
      processed_sections = sections.each_with_index.map do |content, i|
        # use text from the header to build an id
        header_match = content.match(/[a-zA-Z][^<]*/)
        if header_match
          # replace all non-letter-non-digits with minus, merge minus chars, remove trailing minus
          header_id = header_match[0].gsub(/[^a-zA-Z0-9]/, '-').gsub(/\-+/, '-').gsub(/\-$/, '').downcase
        end
        if level < 2 and content
          if content =~ /<\/h#{level}/
            content = "#{$`}#{$&}#{inject_sections($', level+1)}"
          end
        end
        if i == 0
          content
        else
          id_attr = "id='#{header_id}'" if header_id
          "<div class='section#{level}'><h#{level} #{id_attr}" + content + '</div>'
        end
      end
      return processed_sections.join
    end

    def inject_subtopics(orig)
      res = []
      orig.each_line do |line|
        if line =~ /^INCLUDE_HEAD\s(.+)$/
          res << "<iframe class='subtopic' src='#{$1}'></iframe>"
        else
          res << line
        end
      end
      res.join
    end

    def inject_todo(orig)
      res = []
      orig.each_line do |line|
        task = Task.parse(line) # try every line as a task decription
        if task.nil?
          res << line
        elsif task.include_statement?
          recursive = task[:recursive] == 'true' ? ["/#{name}"] : nil
          list = TaskList.from_example(task, recursive)
          res << list.to_html
        else
          res << task.to_html
        end
      end
      res.join
    end

    def inject_links(orig)
      orig # disable wiki words
    end

    def to_s
      name
    end

    def new?
      @blob.id.nil?
    end

    def name
      @blob.name.gsub(/#{File.extname(@blob.name)}$/, '')
    end

    def rel_file_name
      fname = name + self.class.extension
      res = File.join(GitWiki.tree.basename, fname) rescue fname
    end

    def commit_message
      new? ? "Wiki: created #{name}" : "Wiki: updated #{name}"
    end
  end

  class App < Sinatra::Base
    set :app_file, __FILE__
    set :haml, { :format        => :html5,
                 :attr_wrapper  => '"'     }
    enable :inline_templates

    before do
      content_type "text/html", :charset => "utf-8"
      @messages = GitWiki.messages
    end

    get "/" do
      redirect "/" + GitWiki.homepage
    end

    get "/git-wiki-default.css" do
      content_type 'text/css'
      sass :git_wiki_default
    end

    get "/project.css" do
      if (git_obj = GitWiki.tree/'project.css')
        content_type 'text/css'
        body git_obj.data
      else
        halt 404
      end
    end

    get "/git/check" do
      GitWiki.refresh!
      @page = Page.find_or_create(params[:page])
      puts @page.last_change_hash, params[:version]
      if @page.last_change_hash == params[:version]
        return "<div class='last_changed service'>Last change " + @page.last_changed + "</div>"
      else
        return "<div class='warning'>The page you are currently viewing is obsolete.
        Please reload the page.</div>"
      end
    end

    get "/pages" do
      @pages = Page.find_all
      haml :list
    end

    get "/img/*" do
      git_obj = GitWiki.tree/'img'
      params[:splat].each do |part|
        git_obj = git_obj/part
        not_found if git_obj.nil?
      end
      content_type File.extname(params[:splat].last)
      body git_obj.data
    end

    get "/documents/*" do
      git_obj = GitWiki.tree/'documents'
      params[:splat].each do |part|
        git_obj = git_obj/part
        not_found if git_obj.nil?
      end
      mime_type = MIME::Types.type_for(File.extname(params[:splat].last))
      content_type(mime_type.empty? ? 'application/octet-stream' : mime_type)
      body git_obj.data
    end

    get "/:page/edit" do
      @page = Page.find_or_create(params[:page])
      haml :edit
    end

    def render_topic(params) # can be overridden, e.g. in the special git-wiki-crm solution
      @page = Page.find(params[:page])
      if params['head'] == 'head'
        @page.content = @page.content.sub(/\n- - -.*/m, '')
        haml :bare, :layout => :minimal_layout
      else
        haml :show
      end
    end

    get "/:page" do
      begin
        render_topic params
      rescue GitWiki::PageNotFound
        name_or_part = params[:page]

        # search for the part of the topic name (case insensitive)
        @topics = Page.search(name_or_part)

        # render list of suitable topics + 'create new topic'
        haml :select_or_create_topic
      end
    end

    post "/:page" do
      GitWiki.refresh!
      @page = Page.find_or_create(params[:page])
      if GitWiki.delete_if_empty(@page, params[:body])
        redirect "/pages"
      else
        GitWiki.update_content(@page, params[:body])
        redirect "/#{@page}"
      end
    end

    get "/raw/:page" do
      @page = Page.find(params[:page])
      content_type 'text'
      @page.content
    end

    private
      def title(title=nil)
        @title = title.to_s unless title.nil?
        @title
      end

      def list_item(page)
        %Q{<a class="page_name" href="/#{page}">#{page.name}</a>}
      end
  end
end

__END__
@@ git_wiki_default
html, body
  background-color: #DDD
  margin: 0
  padding: 0
  top: 0
  height: 98%
.content
  max-width: 40em
  width: 80%
  background-color: white
  border: 1px solid #888
  padding: 0 10px 8px 8px
  margin-left: 10px
  margin-bottom: 10px
  float: left
.barecontent
  background-color: white
  padding: 0px 0 0 0
  h1
    font-size: 15px
    font-family: FreeSans, sans-serif
    background-color: #AAA
    padding-left: 3px
    color: white
    margin-top: 0
iframe.subtopic
  border: none
  border-top: 1px solid grey
  border-bottom: 1px solid grey
  width: 100%
  height: 20px
form
  height: 92%
#topicContent
  height: 87%
  width: 97%
  margin: 0 1em
del
  color: gray
code
  background-color: #EEEEEE
  border: 1px solid #DDDDDD
  font-family: Consolas,"Andale Mono",monospace
  /*font-size: 0.929em
  /*line-height: 1.385em
  overflow: show
  padding: 2px 4px 0px 4px
pre
  background-color: #EEEEEE
  code
    display: block
    padding: 0.615em 0.46em
    margin-bottom: 1.692em
ul.main_navigation, ul.page_navigation
  list-style-type: none
  display: block
  float: left
  margin: 0
  padding: 0
  li
    display: inline
    margin: 0
    padding: 0
    padding-right: 1.5em
    white-space: nowrap
ul.messages
  border: 1px dashed red
  list-style: none
  font-family: Consolas,"Andale Mono",monospace
  padding: 0
  margin-top: 5em
  font-size: 60%
  overflow: hidden
  display: none
table
  border-collapse: collapse
  border: 1px solid black
  td, th
    border-left: 1px solid black
    border-right: 1px solid black
    border-bottom: 1px dotted lightgrey
    padding: 0px 4px
  th
    border-bottom: 1px solid black
    text-align: left
    padding: 3px 4px
a
  text-decoration: none
  color: inherit
  border-bottom: 1px dotted #8c8c8c
a:visited
  color: inherit
a:hover
  border-bottom: 1px solid #8c8c8c
a.service
  color: #4377EF
  border-bottom: none
  font-weight: bold
a.service:hover
  border-bottom: 2px dotted #4377EF
a.page_name
  border-bottom: 1px dashed #8c8c8c
.desktop.main_navigation, .desktop.page_navigation
  float: left
  font-family: sans-serif
  margin-top: 0
  margin-bottom: 8px
  margin-left: 10px
.desktop.page_navigation
  margin-top: 2.4em
  float: right
.compact.main_navigation, .compact.page_navigation
  display: none
#git-status
  display: none
  float: left
#git-status .warning
  border: 2px solid red
  color: red
  padding: 2px
  margin: 2px
.last_changed
  margin: 0
  font-size: 80%
div.included
  background-color: #eee
  min-height: 3em
  padding: 0
  margin-top: 0.7em
  h2
    padding: 0
    margin: 0
    position: absolute
    right: 1em
    width: auto
    font-weight: normal !important
    text-decoration: none !important
    color: grey
    text-align: right
div.todo p
  display: inline
div.todo a
  border-color: #C0C
div.todo del a
  border-color: grey

body.vimlike
  margin-left: 2em
  font-family: monospace
  div.content
    h1, h2, h3, h4, h5, h6
      font-size: 100%
    h1
      text-decoration: underline
      letter-spacing: 0.3em
    h2
      text-decoration: underline
    ul
      padding-left: 0.3em
      list-style-type: square
      list-style-position: inside
    li ul
      list-style-type: circle
      padding-left: 1.2em
    li ul li ul
      list-style-type: disc

@media print
  .service
    display: none
  div.todo
    line-height: 160%

body.compact
  margin-left: inherit
  font-family: Helvetica, sans-serif
  .desktop.main_navigation, .desktop.page_navigation
    display: none
  .compact.main_navigation, .compact.page_navigation
    display: block
    margin-top: 5px
  .content
    border: none
    margin: 0
    max-width: inherit
    width: 100%
  a
    line-height: 250%

@@ layout
!!!
%html
  %head
    %title= title
    %meta{ :name => "viewport", :content => "width = device-width, user-scalable = yes" }
    %style
      = sass :git_wiki_default
    - if GitWiki.tree/'project.css'
      %style
        = project_specific_css
    %script(src="https://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js" type='text/javascript')
  %body
    %ul.desktop.main_navigation
      %li
        %a.service{ :href => "/#{GitWiki.homepage}" } Home
      %li
        %a.service{ :href => "/pages" } All pages

    #git-status
      Hello

    = yield
    %ul( class="messages")
      -@messages.each do |m|
        %li
          %pre
            %code
              &= m
    %ul.compact.main_navigation
      %li
        %a.service{ :href => "/#{GitWiki.homepage}" } Home
      %li
        %a.service{ :href => "/pages" } All pages
    :javascript
      function toggleCompactView() {
        $('body').toggleClass('compact')
      }
      var uagent = navigator.userAgent.toLowerCase();
      if (uagent.search('mobile') > -1) {
        toggleCompactView()
      }

@@ minimal_layout
!!!
%html
  %head
    %title= title
    %meta{ :name => "viewport", :content => "width = device-width, user-scalable = yes" }
    %link( rel="stylesheet" href="/git-wiki-default.css" type="text/css")
    - if GitWiki.tree/'project.css'
      %link( rel="stylesheet" href="/project.css" type="text/css")
  %body
    = yield

@@ show
- title @page.name
%ul.desktop.page_navigation
  %li
    %a.service{:href => "/#{@page}/edit", :id => 'linkEdit'} Edit
  %li
    %a.service{:href => "javascript:toggleCompactView()"} Compact view
  %li
    %a.service{:href => "/raw/#{@page}"} Raw view
.content{:id=>'content-' + @page.name}
  ~"#{@page.to_html}"
%ul.compact.page_navigation
  %li
    %a.service{:href => "/#{@page}/edit", :id => 'linkEdit'} Edit
  %li
    %a.service{:href => "javascript:toggleCompactView()"} Compact view
  %li
    %a.service{:href => "/raw/#{@page}"} Raw view
:javascript
  document.getElementById("linkEdit").focus();
:javascript
  function autoResizeIFrame() {
    $('iframe').height(
      function() {
        return $(this).contents().find('body').height() + 20;
      }
    )
  }

  $(document).ready(function () {
    $('#git-status').load('/git/check?page=#{@page}&version=#{@page.last_change_hash if @page}', function() {
      $('#git-status').show(300);
    })

    $('iframe').contents().find('body').css({"min-height": "20px", "height": "20px", "overflow" : "hidden"});

    setTimeout(autoResizeIFrame, 2000);
    setTimeout(autoResizeIFrame, 10000);
  })

@@ bare
.barecontent{:id=>'content-' + @page.name}
  ~"#{@page.to_html}"

@@ select_or_create_topic
- title @name_or_part
%br{:style => "clear: both"}
.content
  %ul
    - @topics.each do |topic|
      %li
        %a{:href => "/#{topic}"}
          = topic
  #create-topic
    %a{:href => "/#{@name_or_part}/edit"}
      = "Create topic '#{@name_or_part}'"

@@ edit
- title "Editing #{@page.name}"
%h1= title
%form{:method => 'POST', :action => "/#{@page}"}
  %textarea{:name => 'body', :id => 'topicContent'}= @page.content
  %p
    %input.submit{:type => :submit, :value => "Save as the newest version"}
    or
    %a.cancel{:href=>"/#{@page}"} cancel
:javascript
  document.getElementById("topicContent").focus();

@@ list
- title "Listing pages"
%h1 All pages
- if @pages.empty?
  %p No pages found.
- else
  %ul#list
    - @pages.each do |page|
      %li= list_item(page)
