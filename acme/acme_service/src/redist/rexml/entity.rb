require 'rexml/child'
require 'rexml/source'
require 'rexml/xmltokens'

module REXML
	# God, I hate DTDs.  I really do.  Why this idiot standard still
	# plagues us is beyond me.
	class Entity < Child
		include XMLTokens
		PUBIDCHAR = "\x20\x0D\x0Aa-zA-Z0-9-()+,./:=?;!*@$_%#"
		SYSTEMLITERAL = %Q{((?:"[^"]*")|(?:'[^']*'))}
		PUBIDLITERAL = %Q{("[#{PUBIDCHAR}']*"|'[#{PUBIDCHAR}]*')}
		EXTERNALID = "(?:(?:(SYSTEM)\\s+#{SYSTEMLITERAL})|(?:(PUBLIC)\\s+#{PUBIDLITERAL}\\s+#{SYSTEMLITERAL}))"
		NDATADECL = "\\s+NDATA\\s+#{NAME}"
		PEREFERENCE = "%#{NAME};"
		ENTITYVALUE = %Q{((?:"(?:[^%&"]|#{PEREFERENCE}|#{REFERENCE})*")|(?:'([^%&']|#{PEREFERENCE}|#{REFERENCE})*'))}
		PEDEF = "(?:#{ENTITYVALUE}|#{EXTERNALID})"
		ENTITYDEF = "(?:#{ENTITYVALUE}|(?:#{EXTERNALID}(#{NDATADECL})?))"
		PEDECL = "<!ENTITY\\s+(%)\\s+#{NAME}\\s+#{PEDEF}\\s*>"
		GEDECL = "<!ENTITY\\s+#{NAME}\\s+#{ENTITYDEF}\\s*>"
		ENTITYDECL = /\s*(?:#{GEDECL})|(?:#{PEDECL})/um
		START_RE = /^\s*<!ENTITY/

		attr_reader :name, :external, :ref, :ndata, :pubid

		# Create a new entity.  Simple entities can be constructed by passing a
		# name, value to the constructor; this creates a generic, plain entity
		# reference. For anything more complicated, you have to pass a Source to
		# the constructor with the entity definiton, or use the accessor methods.
		# +WARNING+: There is no validation of entity state except when the entity
		# is read from a stream.  If you start poking around with the accessors,
		# you can easily create a non-conformant Entity.  The best thing to do is
		# dump the stupid DTDs and use XMLSchema instead.
		# 
		#  e = Entity.new( 'amp', '&' )
		def initialize stream, value=nil, parent=nil
			super(parent)
			@reference = false
			@external = nil
			if stream.kind_of? Source
				match = stream.match( ENTITYDECL, true ).to_a.compact
				# Now we have to sort out what kind of entity reference this is,
				# and dereference any internal entities
				if match.include? '%'
					# Reference entity
					@reference = true
					match.delete '%'
				end
				@value = nil
				if match.include? 'SYSTEM'
					# External reference
					@external = 'SYSTEM'
					match.delete @external
					@ref = match[2][1..-2]
					@pubid = @ndata = nil
					@ndata = match[-1] if match.size == 5
				elsif match.include? 'PUBLIC'
					# External reference
					@external = 'PUBLIC'
					match.delete @external
					@pubid = match[2][1..-2]
					@ref = match[3][1..-2]
					@ndata = nil
				else
					@value = match[2][1..-2]
				end
				@name = match[1]
			elsif stream.kind_of? String
				@name = stream
				@value = value
			end
		end

		# Evaluates whether the given string matchs an entity definition,
		# returning true if so, and false otherwise.
		def Entity::matches? string
			(ENTITYDECL =~ string) == 0
		end

		# Evaluates to the unnormalized value of this entity; that is, replacing
		# all entities -- both %ent; and &ent; entities.  This differs from
		# +value()+ in that +value+ only replaces %ent; entities.
		def unnormalized
			v = value()
			return nil if v.nil?
			@unnormalized = Text::unnormalize(v, parent)
			@unnormalized
		end

		#once :unnormalized

		# Returns the value of this entity unprocessed -- raw.  This is the
		# normalized value; that is, with all %ent; and &ent; entities intact
		def normalized
			@value
		end

		# Write out a fully formed, correct entity definition (assuming the Entity
		# object itself is valid.)
		def write out, indent=-1
			out << '<!ENTITY '
			out << '% ' if @reference
			out << @name
			out << ' '
			if @external
				out << @external << ' '
				if @pubid
					q = @pubid.include?('"')?"'":'"'
					out << q << @pubid << q << ' '
				end
				q = @ref.include?('"')?"'":'"'
				out << q << @ref << q
				out << ' NDATA ' << @ndata if @ndata
			else
				q = @value.include?('"')?"'":'"'
				out << q << @value << q
			end
			out << '>'
		end

		# Returns this entity as a string.  See write().
		def to_s
			rv = ''
			write rv
			rv
		end

		PEREFERENCE_RE = /#{PEREFERENCE}/um
		# Returns the value of this entity.  At the moment, only internal entities
		# are processed.  If the value contains internal references (IE,
		# %blah;), those are replaced with their values.  IE, if the doctype
		# contains:
		#  <!ENTITY % foo "bar">
		#  <!ENTITY yada "nanoo %foo; nanoo>
		# then:
		#  doctype.entity('yada').value   #-> "nanoo bar nanoo"
		def value
			if @value
				matches = @value.scan PEREFERENCE_RE
				rv = @value.clone
				if @parent and @parent.document and @parent.document.doc_type
					doctype = @parent.document.doc_type
					matches.each do |entity_reference|
						entity_value = doctype.entity( entity_reference )
						rv.gsub!( /&#{entity_reference};/um, entity_value )
					end
				end
				return rv
			end
			nil
		end

		# Parse an entity from a source stream, notifying a listener of the event
		def Entity::parse_stream source, listener
			listener.entitydecl pull(source)
		end

		# Pull an entity from a source stream, and return an array describing the
		# parsed entity.  The format of the array is completely dependant on the
		# entity type, but in general, internal entities will return:
		# 	[ String entity_name, String entity_value ]
		def Entity::pull source
			match = source.match( ENTITYDECL, true ).to_a.compact
			# Now we have to sort out what kind of entity reference this is
			if match.include? 'SYSTEM'
				# External reference
				match[2] = match[2][1..-2]
			elsif match.include? 'PUBLIC'
				# External reference
				match[2] = match[2][1..-2]
				match[3] = match[3][1..-2]
			elsif match[1] == '%'
				# Parameter entity declaration
				match[3] = match[3][1..-2]
			else
				match[2] = match[2][1..-2]
			end
			match[1..-1]
		end
	end

	# This is a set of entity constants -- the ones defined in the XML
	# specification.  These are +gt+, +lt+, +amp+, +quot+ and +apos+.
	module EntityConst
		# +>+
		GT = Entity.new( 'gt', '>' )
		# +<+
		LT = Entity.new( 'lt', '<' )
		# +&+
		AMP = Entity.new( 'amp', '&' )
		# +"+
		QUOT = Entity.new( 'quot', '"' )
		# +'+
		APOS = Entity.new( 'apos', "'" )
	end
end
