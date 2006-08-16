# Usage
#
#   ofx_instance = OFXRB.import(ofx_doc)
#   ofx_instance.credit_card_statements.each do |cc|
#     puts cc.number
#     puts cc.start_date
#     puts cc.end_date
#   end
#
# See OFXRB::Model to learn more about what objects are available or to define those that
# we have not yet.
module OFXRB

  # Creates an OfxObject for the version detected in the ofx_doc
  def self.import(ofx_doc)
    raise "Not a valid OFX document. Must contain OFXHEADER value." unless ofx_doc =~ /.*?OFXHEADER/
    
    version = $1 if ofx_doc =~ /VERSION:(102)/i
    version ||= $1 if ofx_doc =~ /VERSION="(200)"/
    raise "Unsupported OFX document version" unless version
    
    "OFXRB::Parser#{version}".constantize.parse(ofx_doc)
  end


  # Implements the interface expected by the Parsers
  #
  # This keeps track of the current OFXRB::OfxObject, delegating processing of ofx document events
  # to the current OFXRB::OfxObject. Once the current OFXRB::OfxObject has ended, the previous object is
  # reinstated and regains control of processing, until he has ended, and so on to the end of the document.
  #
  # If you have need of presently unsupported attributes or OFXRB::OfxObject, or just need to know what is
  # already there, please look at ofx_model.rb.
  class OfxHandler

    # All handlers answer the OFX object model that they are building
    attr_reader :ofx_object

    def initialize
      @stack = []
      @current = @ofx_object = Model::OfxInstance.new
    end

    def header_event(name, value)
      @current.ofx_header(name, value)
    end

    def attribute_event(name, value)
      @current.ofx_attr(name, value)
    end

    def start_tag_event(name)
      new_state = @current.ofx_start_tag(name)
      if new_state != @current
        @stack.push(@current)
        @current = new_state
        new_state.ending_name = name
      end
    end
    
    def end_tag_event(name)
      while @current and @current.ofx_end(name)
        @current = @stack.pop
      end
    end

  end


  # All OFXRB::Model classes extend this to provide a DSL that simplifies and clarifies
  # the desired structure of an imported OFX document.
  class OfxObject

    class << self

      def ofx_reverse_lookup_header
        @ofx_reverse_lookup_header ||= Hash.new
      end

      def ofx_paths
        @ofx_paths ||= Hash.new
      end

      def has_attrs(mapping)
        mapping.each do |name, ofx_path|
          ofx_path = [ofx_path] if ofx_path.is_a? String
          ofx_paths[ofx_path] = name
          ofx_attr_accessor(name, :attributes)
        end
      end
    
      def has_one(child_name, ofx_path = [child_name.to_s.upcase])
        ofx_paths[ofx_path] = child_name
        ofx_attr_accessor(child_name, :children)
      end
    
      def has_many(children_name, ofx_path = [children_name.to_s.upcase])
        ofx_paths[ofx_path] = children_name
        ofx_attr_accessor(children_name, :children, 'Array.new')
        module_eval <<-"end;"
          def #{children_name}_add(child)
            send(:#{children_name}) << child
            child
          end
        end;
      end

      def has_header(name, ofx_element = name.to_s.upcase)
        ofx_reverse_lookup_header[ofx_element] = name
        ofx_attr_accessor(name, :headers)
      end
    
      private
      
        # Creates attr_accessor for attr_name
        # <tt>:attr_name</tt>: A Symbol for the desired reader and writer method name
        # <tt>:attr_type</tt>: A Symbol for the name of the instance variable that is the attribute's collection
        # <tt>:default_value</tt>: Optional, a String that would be used to initialize the attribute if it is nil
        def ofx_attr_accessor(attr_name, attr_type, default_value = nil)
          module_eval <<-"end;"
            def #{attr_name}
              @#{attr_type}[:#{attr_name}] ||= #{default_value ? default_value : 'nil'}
            end
            alias :ofx_attr_#{attr_name} :#{attr_name}

            def #{attr_name}=(value)
              @#{attr_type}[:#{attr_name}] = value
            end
            alias :ofx_attr_#{attr_name}= :#{attr_name}=
          end;
        end
    end
    

    attr_writer :ending_name
    
    def initialize
      @ending_name = nil
      @current_path = []
      @children = {}
      @attributes = {}
      @headers = {}
    end

    def attribute(name)
      @attributes[name.to_sym]
    end

    def ofx_attr(ofx_element, value)
      attribute_path = @current_path.dup << ofx_element
      if attribute_name = self.class.ofx_paths[attribute_path]
        self.send("#{attribute_name}=".to_sym, value)
      end
    end

    def ofx_header(ofx_element, value)
      assign = "#{self.class.ofx_reverse_lookup_header[ofx_element]}=".to_sym
      self.send(assign, value) if respond_to? assign
    end
    
    def ofx_start_tag(ofx_element)
      @current_path.push(ofx_element)
      if child_name = self.class.ofx_paths[@current_path]
        if child_name.to_s.plural?
          assign = "#{child_name}_add"
          object_class = child_name.to_s.singularize.camelize
        else
          assign = "#{child_name}="
          object_class = child_name.to_s.camelize
        end
        self.send(assign.to_sym, "OFXRB::Model::#{object_class}".constantize.new)
      else
        self
      end
    end

    def ofx_end(ofx_element)
      @current_path.pop unless @current_path.empty?
      @ending_name == ofx_element
    end

  end

end