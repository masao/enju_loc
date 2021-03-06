class LocSearch
  def initialize( node )
    @node = node
  end
  class ModsRecord < LocSearch
    MODS_NS = { "mods" => "http://www.loc.gov/mods/v3" }
    def title
      title = @node.xpath( './/mods:titleInfo/mods:title', MODS_NS ).first.content
      subtitle = @node.xpath( './/mods:titleInfo/mods:subTitle', MODS_NS ).first
      title += " : #{ subtitle.content }" if subtitle
      title
    end
    def lccn
      @node.xpath( './/mods:identifier[@type="lccn"]', MODS_NS ).first.try( :content )
    end
    def creator
      names = @node.xpath( './/mods:name', MODS_NS )
      creator = names.map do |name|
        name.xpath( './/mods:namePart', MODS_NS ).map do |part|
          if part.content
            part.content
          else
            nil
          end
        end.compact.join( ", " )
      end.join( " ; " )
      creator
    end
    def publisher
      names = @node.xpath( './/mods:publisher', MODS_NS ).map do |e|
        e.content
      end.join( ", " )
    end
    def pubyear
      @node.xpath( './/mods:dateIssued', MODS_NS ).first.try(:content)
    end
  end

  class DCRecord < LocSearch
    DC_NS = { "dc" => "http://purl.org/dc/elements/1.1/" }
    def title
      title = @node.xpath( './/dc:title', DC_NS ).first.content
    end
    def lccn	
      @node.xpath( './/dc:identifier[@type="lccn"]', DC_NS ).first.content
    end
    def creator
    end
  end

  # http://www.loc.gov/z3950/lcserver.html
  LOC_SRU_BASEURL = "http://lx2.loc.gov:210/LCDB"
  def self.make_sru_request_uri( query, options = {} )
    if options[ :page ]
      page = options[ :page ].to_i
      options[ :startRecord ] = ( page - 1 ) * 10 + 1
      options.delete :page
    end
    options = { :maximumRecords => 10, :recordSchema => :mods }.merge( options )
    options = options.merge( { :query => query, :version => "1.1", :operation => "searchRetrieve" } )
    params = options.map do |k, v|
      "#{ URI.escape( k.to_s ) }=#{ URI.escape( v.to_s ) }"
      end.join( '&' )
    uri = "#{ LOC_SRU_BASEURL }?#{ params }"
  end

  def self.search( query, options = {} )
    if query and not query.empty?
      doc = nil
      results = {}
      url = make_sru_request_uri( query, options )
      doc = Nokogiri::XML( open(url) )
      items = doc.search( '//zs:record' ).map{|e| ModsRecord.new e }
      @results = { :items => items,
                   :total_entries => doc.xpath( '//zs:numberOfRecords' ).first.try(:content).to_i }
    else
      { :items => [], :total_entries => 0 }
    end
  end

  def self.import_from_sru_response( lccn )
    identifier = Identifier.where(:body => lccn, :identifier_type_id => IdentifierType.where(:name => 'lccn').first_or_create.id).first
    return if identifier
    url = make_sru_request_uri( "bath.lccn=#{ lccn }" )
    response = Nokogiri::XML( open(url) ).at( '//zs:recordData', {"zs"=>"http://www.loc.gov/zing/srw/"} )
    return unless response.try( :content )
    doc = Nokogiri::XML::Document.new
    doc << response.at( "//mods:mods", { "mods" => "http://www.loc.gov/mods/v3" } )
    Manifestation.import_record_from_loc( doc )
  end
end

