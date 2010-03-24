git-wiki
========

git-wiki is a wiki that relies on git to keep pages' history and
[Sinatra][] to serve them.  This geek brain overlay system aims to
replace trac (wiki and ticket system), a CMS and sticky notes.

Features of this fork (by geekQ)
---------------------

### Support for images

You can add images to `/img` folder of your git repository. Subfolders
are also supported. At least gif, png and jpg supported - content type
is set automatically by Sinatra. You can reference the images then from
your wiki pages like `![My picture](/img/2009/my_picture.jpg)`

No web interface at this time - use `git commit`.


### Custom h1 header

If your wiki page contains a markdown h1 header, then this one is used
on the page. If not, then h1 is created out of the file name (as in
original git-wiki).


### Wiki in a subfolder

You can use git-wiki for documentation of your software project. Simply
put all the content in markdown format into a subfolder, e.g. `wiki` and
provide the folder name as optional parameter.

Example `run.ru` to place in your wiki subfolder:

    #!/usr/bin/env rackup
    #\ -p 8719
    require 'git-wiki' # adjust path to your git-wiki installation if needed
    run GitWiki.new(File.dirname(File.dirname(File.expand_path(__FILE__))), ".markdown", "Home", 'wiki')

You can start the web server now with `./run.ru`.


### Integrated TODO list(s)

Just write TODO or DONE at the beginning of a line with task you would
like to remember.


#### Inclusion

You can include tasks from other wiki pages. So it is possible to have
one separate page per project, e.g. ProjectGitWiki, ProjectWorkflow and
to aggregate all coding tasks on one, say ContextCoding page with
`INCLUDE project:GitWiki`, `INCLUDE project:Workflow`. 

You can also reference other contexts with `INCLUDE context:AtHome`.

Recursion can be turned on with `INCLUDE context:AtHome recursive:true`.
It is off by default.

You can also reference a source on the web. I prefer to manage my tasks
related to git-wiki development in this README file. So on my
ContextCoding page I have following reference: `INCLUDE
http://github.com/geekq/git-wiki/raw/master/README.markdown`

* DONE: include via http
* DONE: recursive inclusion
* DONE: mark included tasks in special way
* DONE: switch recursion on or off
* DONE: avoid endless recursion by saving a list of visited nodes
* TODO: include a task list filtered by tagged value, e.g.  `TASKS context:home` should list all the tasks for the specified context.
* DONE: allow optional asterisk in front of TODO
* TODO: group included lists by project
* TODO: merge and resort tasks from subsequent INCLUDE statements
* DONE: gather all tasks from all pages with `INCLUDE wiki:all`
* TODO: gather all the remaining (not referenced) tasks into `task inventory` page

### No wiki words

For a hacker the wiki words is more a distraction than a help. Example:
if I mention ActiveRecord, than it should not link to the wiki article
ActiveRecord but appear as it is.

* DONE: do not rely on wiki words

### Other plans

* TODO: keyboard short cuts for edit and saving
* TODO: check dead links
* TODO: search engine
* IDEA: presentation system - markdown + my S5 alternative
* IDEA: support for attachments
* IDEA: support for deeper Wiki page folder structure
* IDEA: support for special programmed pages - via haml or liquid template engine


Install
-------

The following [gems][] are required to run git-wiki:

- [Sinatra][]
- [mojombo-grit][]
- [HAML][]
- [RDiscount][]
- [RestClient][]

Run with `mkdir ~/wiki && (cd ~/wiki && git init) && ./run.ru -sthin -p4567`
and point your browser at <http://0.0.0.0:4567/>. Enjoy!

See also
--------

- [How to use vim to edit &lt;textarea&gt; in lynx][tip]
- [WiGit][] think git-wiki except implemented in PHP
- [ikiwiki][] is a wiki compiler supporting git
- git-wiki uses [rdiscount library][] for markdown support. The latest
  version also supports [markdown extra][] like tables, definition
  lists, code blocks without indentation, abbreviations


  [Sinatra]: http://www.sinatrarb.com
  [GitHub]: http://github.com/sr/git-wiki
  [forks]: http://github.com/sr/git-wiki/network
  [al3x]: http://github.com/al3x/gitwiki
  [gems]: http://www.rubygems.org/
  [mojombo-grit]: http://github.com/mojombo/grit
  [HAML]: http://haml.hamptoncatlin.com
  [RDiscount]: http://github.com/rtomayko/rdiscount
  [RestClient]: http://github.com/archiloque/rest-client 
  [tip]: http://wiki.infogami.com/using_lynx_&_vim_with_infogami
  [WiGit]: http://el-tramo.be/software/wigit
  [ikiwiki]: http://ikiwiki.info
  [rdiscount library]: http://rdoc.info/projects/rtomayko/rdiscount
  [markdown extra]: http://michelf.com/projects/php-markdown/extra/

Quotes
------

<blockquote>
<p>[...] the first wiki engine I'd consider worth using for my own projects.</p>
<p><cite>
<a href="http://www.dekorte.com/blog/blog.cgi?do=item&amp;id=3319">
Steve Dekorte</a>
</cite></p>
</blockquote>

<blockquote>
<p>Oh, it looks like <a href="http://atonie.org/2008/02/git-wiki">Git Wiki</a>
may be the starting point for what I need...</p>
<p><cite><a href="http://tommorris.org/blog/2008/03/09#pid2761430">
Tom Morris on "How to build the perfect wiki"</a></cite></p>
</blockquote>

<blockquote>
<p>What makes git-wiki so cool is because it is backed by a git store,
you can clone your wiki just like you could any other git repository.
I’ve always wanted a wiki that I could a.) pull offline when I didn’t
have access to the Internets and b.) edit (perhaps in bulk)
in my favorite text editor. git-wiki allows both.</p>
<p><cite><a href="http://github.com/willcodeforfoo/git-wiki/wikis">
Cloning your wiki</a></cite></p>
</blockquote>

<blockquote>
<p>Numerous people have written diff and merge systems for wikis;
TWiki even uses RCS. If they used git instead, the repository would be tiny, and
you could make a personal copy of the entire wiki to take on the plane with you,
then sync your changes back when you're done.</p>
<p><cite><a href="http://www.advogato.org/person/apenwarr/diary/371.html">
Git is the next Unix</a></cite></p>
</blockquote>


MIT license
-----------
Copyright (c) 2009 Vladimir Dobriakov, <http://blog.geekQ.net>

Copyright (c) Simon Rozet
 
Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:
 
The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.
 
