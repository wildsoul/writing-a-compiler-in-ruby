
require 'pp'
require 'treeoutput'

# FIXME:
#
# Handle symbols that are valid operators but that are not valid in certain circumstances:
#  '}' should cause a return if no '{' has been seen, and should be unget.
#  ',' should cause a return if :call isn't on the opstack?

module OpPrec
  class ShuntingYard
    def initialize output,tokenizer, parser
      @out,@tokenizer,@parser = output,tokenizer,parser
    end

    def reset
      @out.reset
    end
    
    def reduce ostack,op = nil
      pri = op ? op.pri : 0
      # We check for :postfix to handle cases where a postfix operator has been given a lower precedence than an
      # infix operator, yet it needs to bind tighter to tokens preceeding it than a following infix operator regardless,
      # because the alternative gives a malfored expression.
      while  !ostack.empty? && (ostack[-1].pri > pri || ostack[-1].type == :postfix)
        o = ostack.pop
        @out.oper(o) if o.sym
        return if o.type == :lp # FIXME: Check that it is the right :lp
      end
    end

    def parse_block start
      @parser.parse_block(start)
    end

    def shunt src, ostack = []
      possible_func = false     # was the last token a possible function name?
      opstate = :prefix         # IF we get a single arity operator right now, it is a prefix operator
                                # "opstate" is used to handle things like pre-increment and post-increment that
                                # share the same token.

      opcall  = Operators["#call#"]
      opcallm = Operators["#callm#"]
      lastlp = true
      src.each do |token,op|
        if op
          if op.sym == :hash_or_block || op.sym == :block
            if possible_func || ostack.last == opcall || ostack.last == opcallm
              @out.value([]) if ostack.last != opcall
              @out.value(parse_block(token))
              @out.oper(Operators["#flatten#"])
              ostack << opcall if ostack.last != opcall
            elsif op.sym == :hash_or_block
              op = Operators["#hash#"]
            else
              raise "Block not allowed here"
            end
          else
            if op.type == :rp
              @out.value(nil) if lastlp
              src.unget(token) if !ostack.last || !ostack.last.type == :lp  || !ostack.last.sym == :call
            end
            reduce(ostack,op)
            if op.type == :lp
              shunt(src,[op]) 
              # Handling function calls and a[1] vs [1]
              ostack << (op.sym == :array ? Operators["#index#"] : opcall) if possible_func
            elsif op.type == :rp
              return nil
            else
              opstate = :prefix
              ostack << op
            end
          end
        else 
          if possible_func
            reduce(ostack)
            ostack << opcall
          end
          @out.value(token)
          opstate = :infix_or_postfix # After a non-operator value, any single arity operator would be either postfix,
                                      # so when seeing the next operator we will assume it is either infix or postfix.
        end
        possible_func = !op && !token.is_a?(Numeric)
        lastlp = false
      end

      if opstate == :prefix && ostack.size && ostack.last && ostack.last.type == :prefix
        # This is an error unless the top of the @ostack has minarity == 0,
        # which means it's ok for it to be provided with no argument
        if ostack.last.minarity == 0
          @out.value(nil)
        else
          raise "Missing value for prefix operator #{ostack[-1].sym.to_s}"
        end
      end

      reduce(ostack)
      return @out if  ostack.empty?
      raise "Syntax error. #{ostack.inspect}"
    end
    
    def parse
      reset
      res = shunt(@tokenizer)
      res ? res.result : nil
    end
  end

  def self.parser scanner, parser
     ShuntingYard.new(TreeOutput.new,Tokens::Tokenizer.new(scanner), parser)
  end

end
