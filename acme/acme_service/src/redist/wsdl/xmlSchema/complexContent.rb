=begin
WSDL4R - XMLSchema complexContent definition for WSDL.
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


class ComplexContent < Info
  attr_accessor :base
  attr_reader :deriveType
  attr_reader :content
  attr_reader :attributes

  def initialize
    super
    @base = nil
    @deriveType = nil
    @content = nil
    @attributes = NamedElements.new
  end

  def parseElement( element )
    case element
    when RestrictionName, ExtensionName
      @deriveType = element.name
      self
    when AllName, SequenceName, ChoiceName
      if @deriveType.nil?
	raise WSDLParser::ElementConstraintError.new( "base attr not found." )
      end
      @content = Content.new
      @content.type = element.name
      @content
    when AttributeName
      if @deriveType.nil?
	raise WSDLParser::ElementConstraintError.new( "base attr not found." )
      end
      o = Attribute.new
      @attributes << o
      o
    end
  end

  def parseAttr( attr, value )
    if @deriveType.nil?
      raise WSDLParser::UnknownAttributeError.new( "Unknown attr #{ attr }." )
    end
    case attr
    when BaseAttrName
      @base = value
    else
      raise WSDLParser::UnknownAttributeError.new( "Unknown attr #{ attr }." )
    end
  end
end

  end
end
