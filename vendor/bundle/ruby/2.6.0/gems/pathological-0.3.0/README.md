# Pathological

Pathological is a Ruby tool that provides a lightweight mechanism for managing your project's load path.

[![Build Status](https://secure.travis-ci.org/ooyala/pathological.png)](http://travis-ci.org/ooyala/pathological)

## The problem

When you're writing a gem, you don't have to worry about paths much, because Rubygems makes sure that `lib/`
makes it into your path for you. On the other hand, if you have large Ruby projects which aren't organized as
gems, you may encounter some of the following problems:

  * If you don't have relative requires, you have to run your project from the project root.
  * If you want relative requires, you have something nasty like this in your code:

        require File.expand_path(File.join(File.dirname(__FILE__), 'myfile'))

  * Ruby 1.9.2 breaks your load path if you are expecting `.` to be in it. You might have to use
    `require_relative` or similar to remedy this.
  * You have symlinks to shared libraries or non-gemified vendor code living all over your project in order
    to keep your load paths sane.

Pathological provides one way to manage these issues.

## Using pathological

Getting started with pathological is easy. First, make a file called `Pathfile` at your project root:

    $ cd path/to/myproject
    $ touch Pathfile

Now require the gem at the start of any executable ruby file:

``` ruby
#!/usr/bin/env ruby

require "bundler/setup" # If you're using bundler
require "pathological"

# other requires...
```

Now your project root will be in your load path. If your project has, for example, `lib/foo.rb`, then `require
lib/foo` will work in any of your ruby files. This works because when Pathological is required it will search
up the directory tree until it finds a `Pathfile`. (It will raise an error if one cannot be found).

Note that Pathological should be the first require in your main file so that it will be loaded first. An
exception to this is when you're using Bundler, in which case you should `require bundler/setup` before
Pathological (and of course you should have `gem "pathological"` in your `Gemfile`).

`Pathfile`s should be kept in version control.

## Adding other paths to your load path

To add more paths to your load path, just put the paths in your `Pathfile`. The paths are relative to the
location of the `Pathfile`. The paths will be inserted in the order they appear; the project root itself will
be first. If any of the paths are not valid directories, then an exception will be raised when Pathological is
required.

#### Example

Suppose that you have a directory structure like this:

    repos/
    |-shared_lib/
    | `-common.rb
    `-my_project/
      |-Pathfile
      |-run_my_project.rb
      `-foo.rb

and that `Pathfile` contains the following:

    ../shared_lib

Then inside `run_my_project.rb`:

``` ruby
require "pathological"
require "foo"
require "common"
# ...
```

## Installation

Pathological is packaged as a Rubygem and hence can be trivially installed with

    $ gem install pathological

## Advanced usage

In some cases, you might want slightly different behavior. This customization is done through the use of
custom modes. You may use any combination of modes.

#### debug

This adds debugging statements to `STDOUT` that explain what Pathological is doing.

#### excluderoot

In this mode, the project root (where the `Pathfile` is located) is not added to the load path (so only paths
specified *in* the `Pathfile` will be loaded).

#### noexceptions

This is used if you don't want to raise exceptions if you have bad paths (i.e. non-existent paths or not
directories) in your `Pathfile`.

#### bundlerize

Bundlerize mode enables Bundler to work with your project regardless of your current directory, in the same
way as Pathological, by attempting to set the `BUNDLE_GEMFILE` environment variable to match the directory
where the `Pathfile` is located. Note that you have to run this before requiring `bundler/setup`. Also, this
will not take effect if you are running with `bundle exec`.

#### parentdir

This mode makes Pathological add the unique parents of all paths it finds (instead of the paths themselves).
The purpose of parentdir is to enable Pathological to work in a drop-in fashion with legacy code written with
all requires being relative to the root of the codebase. Note that this will allow one to require files
located in any child of the parents, not just from the directories specified in the `Pathfile`. This mode
should be avoided if possible.

There are two ways to specify modes. First, you can enable any modes you want using the Pathological API:

``` ruby
require "pathological/base"
Pathological.debug_mode
Pathological.parentdir_mode
Pathological.add_paths!
```

A quicker way is also provided: if you only need to use one special mode, then there is a dedicated file you
can require:

``` ruby
require "pathological/debug"
```

## Public API

For even more configurable custom integration with Pathological, a public API is provided. See the generated
documentation for details on the following public methods:

* `Pathological#add_paths!`
* `Pathological#find_load_paths`
* `Pathological#find_pathfile`
* `Pathological#reset!`
* `Pathological#copy_outside_paths!`

## Notes and gotchas

Pathological is intended as a replacement for manually munging the load path in your application when you want
to load code from other locations. If you can turn each of your dependencies into a gem and then use bundler
to manage the dependencies, **do that instead**.

Pathological does its best to figure out where the Pathfile it should use is located, based on the call stack.
For instance, if you run `/foo/bar.rb` and that requires Pathological, then it will search for `/foo/Pathfile`
and -- failing that -- `/Pathfile`. However, if `/foo/bar.rb` does not require Pathological, but loads a ruby
file in `/baz/quux.rb`, and *that* file requires Pathological, then Pathological searches for `/baz/Pathfile`
and then `/Pathfile`.

Any code loading situation which does not preserve a sane load path will be incompatible with Pathological.
For instance, if you `eval()` some code that requires Pathological, Pathological has no way of telling where
that code originally lived, and will probably behave in an unexpected way. One place this commonly occurs is
with rack webservers (e.g., Rackup, Unicorn) that load a `config.ru`. This file is `instance_eval`ed and so
requiring Pathological from your `config.ru` will not work as expected. In these cases, require Pathological
in your app directly.

## Authors

Pathological was written by the following Ooyala engineers:

* [Daniel MacDougall](mailto:dmac@ooyala.com)
* [Caleb Spare](mailto:caleb@ooyala.com)
* [Sami Abu-El-Haija](mailto:sami@ooyala.com)
* [Evan Chan](mailto:ev@ooyala.com)

## Credits

* Harry Robertson for the idea to *not* use a dot-prefixed configuration file

## Metadata

* [Hosted on Github](https://github.com/ooyala/pathological)
* [Rubygems page](https://rubygems.org/gems/pathological)
* [Documentation](http://rubydoc.info/github/ooyala/pathological/master/frames)

## Contributing

If you would like to commit a patch, great! Just do the usual github pull request stuff and we'll check it
out[.](http://www.randomkittengenerator.com/)

## License

Pathological is licensed under the MIT license.
