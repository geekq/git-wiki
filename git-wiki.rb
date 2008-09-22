#!/usr/bin/env ruby
$:.unshift *Dir[File.dirname(__FILE__) + '/vendor/**/lib'].to_a
%w(sinatra
grit
rubygems
haml
sass
bluecloth).each { |dependency| require dependency }

begin
  require 'thin'
rescue LoadError
  puts '# May I suggest you to use Thin?'
end

class String
  def to_html
    BlueCloth.new(self).to_html.linkify
  end

  def linkify
    self.gsub(/([A-Z][a-z]+[A-Z][A-Za-z0-9]+)/) do |page|
      "<a class='#{Page.new(page).tracked? ? 'exists' : 'unknown'}' href='#{page}'>#{page.titleize}</a>"
    end
  end

  def titleize
    self.gsub(/([A-Z]+)([A-Z][a-z])/,'\1 \2').gsub(/([a-z\d])([A-Z])/,'\1 \2')
  end

  def without_ext
    self.sub(File.extname(self), '')
  end
end

class Page
  class << self
    attr_accessor :repo

    def find_all
      return [] if Page.repo.tree.contents.empty?
      traverse_tree Page.repo.tree
    end

    def traverse_tree(tree)
      articles = []
      tree.contents.collect do |elem|
        if elem.respond_to?(:contents)
          articles += traverse_tree(elem)
        else
          articles << Page.new(elem.name.without_ext)
        end
      end
      articles
    end
  end

  attr_reader :name, :path

  def initialize(name, init_path = nil)
    @name = name
    @path = init_path || name + PageExtension
  end

  def body
    if binary?
      puts "raw output"
      raw_body
    else
      raw_body.to_html
    end
  end

  def binary?
    !(path =~ /#{PageExtension}$/)
  end

  def raw_body
    tracked? ? find_blob.data : ''
  end

  def body=(content)
    return if content == raw_body
    File.open(file_name, 'w') { |f| f << content }
    add_to_index_and_commit!
  end

  def tracked?
    !find_blob.nil?
  end

  def to_s
    name
  end

  private
    def find_blob
      go_deeper Page.repo.tree, path.split('/')
    end

    def go_deeper(tree, folders)
      sub_elem = tree/(folders.shift)
      folders.empty? ? sub_elem : go_deeper(sub_elem, folders)
    end

    def add_to_index_and_commit!
      Dir.chdir(GitRepository) { Page.repo.add(base_name) }
      Page.repo.commit_index(commit_message)
    end

    def file_name
      File.join(GitRepository, path)
    end

    def base_name
      File.basename(file_name)
    end

    def commit_message
      tracked? ? "Edited #{name}" : "Created #{name}"
    end
end

use_in_file_templates!

configure do
  GitRepository = ENV['GIT_WIKI_REPO'] || File.join(ENV['HOME'], 'wiki')
  PageExtension = '.markdown'
  Homepage = 'Home'
  set_option :haml,  :format        => :html4,
                     :attr_wrapper  => '"'

  begin
    Page.repo = Grit::Repo.new(GitRepository)
  rescue Grit::InvalidGitRepositoryError, Grit::NoSuchPathError
    abort "#{GitRepository}: Not a git repository. Install your wiki with `rake bootstrap`"
  end
end

helpers do
  def title(title=nil)
    @title = title.to_s unless title.nil?
    @title
  end

  def list_item(page)
    '<a class="page_name" href="/%s">%s</a>' % [page, page.name.titleize]
  end
end

before { content_type 'text/html', :charset => 'utf-8' }

get('/') { redirect '/' + Homepage }

get '/_stylesheet.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :stylesheet
end

get '/_list' do
  @pages = Page.find_all
  haml :list
end

get '/:page' do
  @page = Page.new(params[:page])
  @page.tracked? ? haml(:show) : redirect("/e/#{@page.name}")
end

get '/:page.txt' do
  @page = Page.new(params[:page])
  throw :halt, [404, "Unknown page #{params[:page]}"] unless @page.tracked?
  content_type 'text/plain', :charset => 'utf-8'
  @page.raw_body
end

get '/e/:page' do
  @page = Page.new(params[:page])
  haml :edit
end

post '/e/:page' do
  @page = Page.new(params[:page])
  @page.body = params[:body]
  request.xhr? ? @page.body : redirect("/#{@page.name}")
end

get '/*' do
  @page = Page.new('hello', params['splat'].to_s)
  if @page.tracked?
    if @page.binary?
      content_type ''
      @page.raw_body
    else
      haml(:show)
    end
  else
    redirect("/e/#{@page.name}")
  end
end

__END__
@@ layout
!!! strict
%html
  %head
    %title= title
    %link{:rel => 'stylesheet', :href => '/_stylesheet.css', :type => 'text/css'}
    - Dir[Sinatra.application.options.public + '/*.js'].sort.each do |lib|
      %script{:src => "/#{File.basename(lib)}", :type => 'text/javascript'}
    :javascript
      $(document).ready(function() {
        $.hotkeys.add('Ctrl+h', function() { document.location = '/#{Homepage}' })
        $.hotkeys.add('Ctrl+l', function() { document.location = '/_list' })

        /* title-case-ification */
        document.title = document.title.toTitleCase();
        $('h1:first').text($('h1:first').text().toTitleCase());
        $('a').each(function(i) {
          var e = $(this)
          e.text(e.text().toTitleCase());
        })
      })
  %body
    #content= yield

@@ show
- title @page.name.titleize
:javascript
  $(document).ready(function() {
    $.editable.addInputType('autogrow', {
      element : function(settings, original) {
        var textarea = $('<textarea>');
        if (settings.rows) {
          textarea.attr('rows', settings.rows);
        } else {
          textarea.height(settings.height);
        }
        if (settings.cols) {
          textarea.attr('cols', settings.cols);
        } else {
          textarea.width(settings.width);
        }
        $(this).append(textarea);
        return(textarea);
      },
      plugin : function(settings, original) {
        $('textarea', this).autogrow(settings.autogrow);
      }
    });

    $('#page_content').editable('/e/#{@page}', {
      loadurl: '/#{@page}.txt',
      submit: '<button class="submit" type="submit">Save as the newest version</button>',
      cancel: '<a class="cancel" href="" style="margin-left: 5px;">cancel</a>',
      event: 'dblclick',
      type: 'autogrow',
      cols: 84,
      rows: 20,
      name: 'body',
      onblur: 'ignore',
      tooltip: ' ',
      indicator: 'Saving...',
      loadtext: '',
      cssclass: 'edit_form',
    })
  })
%h1= title
#page_content
  ~"#{@page.body}"

@@ edit
- title "Editing #{@page.name.titleize}"
%h1= title
%form{:method => 'POST', :action => "/e/#{@page}"}
  %p
    %textarea{:name => 'body', :rows => 16, :cols => 60}= @page.raw_body
  %p
    %input.submit{:type => :submit, :value => 'Save as the newest version'}
    or
    %a.cancel{:href=>"/#{@page}"} cancel

@@ list
- title "Listing pages"
%h1 All pages
- if @pages.empty?
  %p No pages found.
- else
  %ul#pages_list
    - @pages.each_with_index do |page, index|
      - if (index % 2) == 0
        %li.odd=  list_item(page)
      - else
        %li.even= list_item(page)

@@ stylesheet
body
  :font
    family: "Lucida Grande", Verdana, Arial, Bitstream Vera Sans, Helvetica, sans-serif
    size: 14px
    color: black
  line-height: 160%
  background-color: white
  margin: 0
  padding: 0
#content
  padding: 2em
a
  padding: 2px
  color: blue
  &.exists
    &:hover
      background-color: blue
      text-decoration: none
      color: white
  &.unknown
    color: gray
    &:hover
      background-color: gray
      color: white
      text-decoration: none
  &.cancel
    color: red
    &:hover
      text-decoration: none
      background-color: red
      color: white
textarea
  font-family: courrier
  font-size: 14px
  line-height: 18px
  padding: 5px
button.submit
  font-weight: bold
ul#pages_list
  list-style-type: none
  margin: 0
  padding: 0
  li
    padding: 5px
    &.odd
      background-color: #D3D3D3
