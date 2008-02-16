DCBot is a Direct Connect bot written in Ruby.
It has an extensible plugin architecture backed by a database
and comes with a plugin to manage requests.

Dependencies
============

- RubyGems
- ActiveRecord
- EventMachine

Usage
=====

Edit dcbot.conf and then run dcbot.rb.
Typing text into standard input will send it as messages to hub chat.

Notes
=====

At this time, only one hub connection is supported. It should be easy to add multiple hubs,
but I didn't need it and I wasn't sure how to handle keyboard input in that case.

Also, please note that this is a fairly quick and dirty bot, so don't be surprised if some
of the architecture is suboptimal.

Author
======

Kevin Ballard <kevin@sb.org>
