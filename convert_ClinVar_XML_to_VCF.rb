require 'ox'
require 'cgi'
require 'uri'

# Parse the ClinVar XML file
#
# Example usage:
#   ruby ox_parse.rb

CLINVAR = "ClinVarFullRelease_2015-09.xml"
#CLINVAR = "ClinVar.example.xml"
#CLINVAR = "examples/RCV000077146.xml"

ASSEMBLY = 'GRCh37'

class ClinVarParser < ::Ox::Sax
  ##
  # Initialize
  ##
  def initialize
    @element_parents = [] # stack of embedded elements
    @attr_sibs = {} # siblings of the current attribute
  end

  ##
  # Start of element
  ##
  def start_element(name)
    # Update current element and element stack
    @element_parents << name.to_s
    @cur_element = @element_parents.last
    @attr_sibs = {}

    # Begin new variant record
    if @cur_element == "ClinVarSet"
      @record = {}
      @record[:chrom] = '.'
      @record[:pos] = '.'
      @record[:rsid] = '.'
      @record[:ref] = '.'
      @record[:alt] = '.'
      @record[:info] = {}
      @record[:info][:pubmed_ids] = []
      @record[:info][:pathogenicities] = []
      @record[:info][:reviews] = []
    end
  end

  ##
  # Element attributes
  ##
  def attr(name, value)
    @cur_attr = name.to_s
    @cur_attr_val = value.to_s
    @attr_sibs[@cur_attr] = @cur_attr_val

    # Get CHROM, POS, REF, and ALT
    if @cur_element == "SequenceLocation" && @element_parents[-2] == "Measure"
      if @cur_attr == "Chr" && @attr_sibs['Assembly'] == ASSEMBLY
        @record[:chrom] = @cur_attr_val
      elsif @cur_attr == "start" && @attr_sibs['Assembly'] == ASSEMBLY
        @record[:pos] = @cur_attr_val
      elsif @cur_attr == "referenceAllele" && @attr_sibs['Assembly'] == ASSEMBLY
        @record[:ref] = @cur_attr_val
      elsif @cur_attr == "alternateAllele" && @attr_sibs['Assembly'] == ASSEMBLY
        @record[:alt] = @cur_attr_val
      end
    end

    # Get rsID
    if @cur_element == "XRef"
      if @cur_attr == "ID" && @attr_sibs['Type'] == 'rs'
        @record[:rsid] = "rs#{@cur_attr_val}"
      end
    end
  end

  ##
  # Element value
  ##
  def text(value)
    if @cur_element == "Title"
      # HGVS name
      @record[:info][:hgvs] = URI.escape(CGI.unescapeHTML(value.sub(/ AND .*/, '')))
    elsif @cur_element == "Description" && @element_parents[-2] == "ClinicalSignificance"
      # Pathogenicity
      @record[:info][:pathogenicities] << value
    elsif @cur_element == "ReviewStatus" && @element_parents[-2] == "ClinicalSignificance"
      # Review status
      @record[:info][:reviews] << URI.escape(value)
    elsif @cur_element == "ID" && @cur_attr == "Source" && @cur_attr_val == "PubMed"
      # PubMed IDs
      @record[:info][:pubmed_ids] << value
    end
  end

  ##
  # End of element
  ##
  def end_element(name)
    # Update current element and element stack
    @cur_element = @element_parents.pop

    if @cur_element == "ClinVarSet"
      # Prepare fields for printing
      info = "CLINVAR_PATHOGENICITY=#{@record[:info][:pathogenicities].join('|')}"
      info += ";CLINVAR_REVIEWS=#{@record[:info][:reviews].join('|')}"
      info += ";CLINVAR_PMID=#{@record[:info][:pubmed_ids].uniq.join('|')}"
#      info += ";CLINVAR_HGVS=#{@record[:info][:hgvs]}"

      # Print record
      puts [@record[:chrom], @record[:pos], @record[:rsid], @record[:ref], @record[:alt], '.', '.', info].join("\t")
    end
  end
end

# Begin parser
handler = ClinVarParser.new()
File.open(CLINVAR) do |f| 
  Ox.sax_parse(handler, f)
end
