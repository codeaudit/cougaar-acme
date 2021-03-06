=begin
WSDL4R - XMLSchema complexType definition for WSDL.
Copyright (C) 2002 NAKAMURA Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'wsdl/info'


module WSDL
  module XMLSchema


class Content < Info
  attr_accessor :final
  attr_accessor :mixed
  attr_accessor :type
  attr_reader :contents
  attr_reader :elements

  def initialize
    super()
    @final = nil
    @mixed = false
    @type = nil
    @contents = []
    @elements = []
  end

  def targetNamespace
    parent.targetNamespace
  end

  def <<( content )
    @contents << content
    updateElements
  end

  def each
    @contents.each do | content |
      yield content
    end
  end

  def parseElement( element )
    case element
    when AllName, SequenceName, ChoiceName
      o = Content.new
      o.type = element.name
      @contents << o
      o
    when ElementName
      o = Element.new
      @contents << o
      o
    else
      nil
    end
  end

  def parseAttr( attr, value )
    case attr
    when FinalAttrName
      @final = value
    when MixedAttrName
      @mixed = ( value == 'true' )
    else
      raise WSDLParser::UnknownAttributeError.new( "Unknown attr #{ attr }." )
    end
  end

  def postParse
    updateElements
  end

private

  def updateElements
    @elements = []
    @contents.each do | content |
      if content.is_a?( Element )
	@elements << [ content.name, content ]
      end
    end
  end
end

  end
end
