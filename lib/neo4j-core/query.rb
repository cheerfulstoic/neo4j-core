require 'neo4j-core/query_clauses'

module Neo4j::Core
  # Allows for generation of cypher queries via ruby method calls (inspired by ActiveRecord / arel syntax)
  #
  # Can be used to express cypher queries in ruby nicely, or to more easily generate queries programatically.
  #
  # Also, queries can be passed around an application to progressively build a query across different concerns
  #
  # See also the following link for full cypher language documentation:
  # http://docs.neo4j.org/chunked/milestone/cypher-query-lang.html
  class Query
    include Neo4j::Core::QueryClauses

    def initialize(options = {})
      @options = options
      @clauses = []
    end

    # @method start *args
    # START clause
    # @return [Query]

    # @method match *args
    # MATCH clause
    # @return [Query]

    # @method optional_match *args
    # OPTIONAL MATCH clause
    # @return [Query]

    # @method using *args
    # USING clause
    # @return [Query]

    # @method where *args
    # WHERE clause
    # @return [Query]

    # @method with *args
    # WITH clause
    # @return [Query]

    # @method order *args
    # ORDER BY clause
    # @return [Query]

    # @method limit *args
    # LIMIT clause
    # @return [Query]

    # @method skip *args
    # SKIP clause
    # @return [Query]

    # @method set *args
    # SET clause
    # @return [Query]

    # @method remove *args
    # REMOVE clause
    # @return [Query]

    # @method unwind *args
    # UNWIND clause
    # @return [Query]

    # @method return *args
    # RETURN clause
    # @return [Query]

    # @method create *args
    # CREATE clause
    # @return [Query]

    # @method create_unique *args
    # CREATE UNIQUE clause
    # @return [Query]

    # @method merge *args
    # MERGE clause
    # @return [Query]

    # @method delete *args
    # DELETE clause
    # @return [Query]

    %w[start match optional_match using where with order limit skip set remove unwind return create create_unique merge delete].each do |clause|
      clause_class = clause.split('_').map {|c| c.capitalize }.join + 'Clause'
      module_eval(%Q{
        def #{clause}(*args)
          build_deeper_query(#{clause_class}, args)
        end}, __FILE__, __LINE__)
    end

    alias_method :offset, :skip
    alias_method :order_by, :order

    # Works the same as the #set method, but when given a nested array it will set properties rather than setting entire objects
    # @example
    #    # Creates a query representing the cypher: MATCH (n:Person) SET n.age = 19
    #    Query.new.match(n: :Person).set_props(n: {age: 19})
    def set_props(*args)
      build_deeper_query(SetClause, args, set_props: true)
    end

    # Allows what's been built of the query so far to be frozen and the rest built anew.  Can be called multiple times in a string of method calls
    # @example
    #   # Creates a query representing the cypher: MATCH (q:Person), r:Car MATCH (p: Person)-->q
    #   Query.new.match(q: Person).match('r:Car').break.match('(p: Person)-->q')
    def break
      build_deeper_query(nil)
    end

    def response
      Neo4j::Session.current._query(self.to_cypher) # TODO: Support params
    end

    # Returns a CYPHER query string from the object query representation
    # @example
    #    Query.new.match(p: :Person).where(p: {age: 30})  # => "MATCH (p:Person) WHERE p.age = 30
    #
    # @return [String] Resulting cypher query string
    def to_cypher
      cypher_string = partitioned_clauses.map do |clauses|
        clauses_by_class = clauses.group_by(&:class)

        cypher_parts = [WithClause, CreateClause, CreateUniqueClause, MergeClause, StartClause, MatchClause, OptionalMatchClause, UsingClause, WhereClause, SetClause, RemoveClause, UnwindClause, DeleteClause, ReturnClause, OrderClause, LimitClause, SkipClause].map do |clause_class|
          clauses = clauses_by_class[clause_class]

          clause_class.to_cypher(clauses) if clauses
        end

        cypher_string = cypher_parts.compact.join(' ')
        cypher_string.strip
      end.join ' '

      cypher_string = "CYPHER #{@options[:parser]} #{cypher_string}" if @options[:parser]
      cypher_string.strip
    end

    # Returns a CYPHER query specifying the union of the callee object's query and the argument's query
    #
    # @example
    #    # Generates cypher: MATCH (n:Person) UNION MATCH (o:Person) WHERE o.age = 10
    #    q = Neo4j::Core::Query.new.match(o: :Person).where(o: {age: 10})
    #    result = Neo4j::Core::Query.new.match(n: :Person).union_cypher(q)
    #
    # @param other_query [Query] Second half of UNION
    # @param options [Hash] Specify {all: true} to use UNION ALL
    # @return [String] Resulting UNION cypher query string
    def union_cypher(other_query, options = {})
      "#{self.to_cypher} UNION#{options[:all] ? ' ALL' : ''} #{other_query.to_cypher}"
    end

    protected

    def add_clauses(clauses)
      @clauses += clauses
    end

    private

    def build_deeper_query(clause_class, args = {}, options = {})
      self.dup.tap do |new_query|
        new_query.add_clauses [nil] if [nil, WithClause].include?(clause_class)
        new_query.add_clauses clause_class.from_args(args, options) if clause_class
      end
    end

    def break_deeper_query
      self.dup.tap do |new_query|
        new_query.add_clauses [nil]
      end
    end

    def partitioned_clauses
      partitioning = [[]]

      @clauses.each do |clause|
        if clause.nil? && partitioning.last != []
          partitioning << []
        else
          partitioning.last << clause
        end
      end

      partitioning
    end
  end
end



