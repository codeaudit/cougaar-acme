# REXML is an XML parser for Ruby, in Ruby.
# 
# URL: http://www.germane-software.com/software/rexml
# Author: Sean Russell <ser@germane-software.com>
# Version: 2.5.3
# Date: +2002/356


# 
# Short Description:
# Why did I write REXML?   At the time of this writing, there were already
# two XML parsers for Ruby. The first is a Ruby binding to a native XML
# parser.  This is a fast parser, using proven technology. However,
# it isn't very portable. The second is a native Ruby implementation, but
# I didn't like its API very much.  I wrote REXML for myself, so that I'd
# have an XML parser that had an intuitive API.
#
# API documentation can be downloaded from the REXML home page, or can
# be accessed online at http://www.germane-software.com/software/rexml_doc
# A tutorial is available in docs/tutorial.html
module REXML
	VERSION_MAJOR = 2
	VERSION_MINOR = 5
	RELEASE = 3
	Copyright = 'Copyright #{Time.now.year} Sean Russell <ser@germane-software.com>'
	Date = "+2002/356
"
	Version = "#{VERSION_MAJOR}.#{VERSION_MINOR}.#{RELEASE}"
end
