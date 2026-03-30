//+------------------------------------------------------------------+
//| SD_ExprParser.mqh                                                |
//| Recursive-descent parser and explicit AST for expressions.         |
//| Memory: tree owned by caller; delete via SdAst_Free(root).        |
//+------------------------------------------------------------------+
#ifndef __SD_EXPR_PARSER_MQH__
#define __SD_EXPR_PARSER_MQH__

#include "SD_Config.mqh"
#include "SD_Types.mqh"
#include "SD_ExprLexer.mqh"

#define SD_AST_NUMBER       1
#define SD_AST_UNARY_MINUS  2
#define SD_AST_BINARY       3
#define SD_AST_SERIES       4
#define SD_AST_SHIFT        5
#define SD_AST_CALL         6
#define SD_AST_BANDS        7

#define SD_SER_OPEN         0
#define SD_SER_HIGH         1
#define SD_SER_LOW          2
#define SD_SER_CLOSE        3
#define SD_SER_VOLUME       4

#define SD_BAND_UPPER       0
#define SD_BAND_LOWER       1
#define SD_BAND_MID         2

//+------------------------------------------------------------------+
//| Base node; concrete types own child pointers (virtual dtor).      |
//+------------------------------------------------------------------+
class SdAstNode
  {
public:
   int               m_kind;
                     SdAstNode(const int kind) : m_kind(kind) {}
   virtual           ~SdAstNode() {}
  };

//+------------------------------------------------------------------+
class SdAstNumber : public SdAstNode
  {
public:
   double            m_value;
                     SdAstNumber(const double value) : SdAstNode(SD_AST_NUMBER), m_value(value) {}
  };

//+------------------------------------------------------------------+
class SdAstUnaryMinus : public SdAstNode
  {
public:
   SdAstNode         *m_child;
                     SdAstUnaryMinus(SdAstNode *child) : SdAstNode(SD_AST_UNARY_MINUS), m_child(child) {}
   virtual           ~SdAstUnaryMinus() { if(m_child != NULL) delete m_child; }
  };

//+------------------------------------------------------------------+
class SdAstBinary : public SdAstNode
  {
public:
   SdAstNode         *m_left;
   SdAstNode         *m_right;
   int               m_op;
                     SdAstBinary(const int op, SdAstNode *left, SdAstNode *right)
                        : SdAstNode(SD_AST_BINARY), m_left(left), m_right(right), m_op(op) {}
   virtual           ~SdAstBinary()
                       {
                        if(m_left != NULL)  delete m_left;
                        if(m_right != NULL) delete m_right;
                       }
  };

//+------------------------------------------------------------------+
class SdAstSeries : public SdAstNode
  {
public:
   int               m_series;
                     SdAstSeries(const int series_kind) : SdAstNode(SD_AST_SERIES), m_series(series_kind) {}
  };

//+------------------------------------------------------------------+
class SdAstShift : public SdAstNode
  {
public:
   SdAstNode         *m_inner;
   int               m_shift;
                     SdAstShift(SdAstNode *inner, const int shift_bars)
                        : SdAstNode(SD_AST_SHIFT), m_inner(inner), m_shift(shift_bars) {}
   virtual           ~SdAstShift() { if(m_inner != NULL) delete m_inner; }
  };

//+------------------------------------------------------------------+
class SdAstCall : public SdAstNode
  {
public:
   string            m_name;
   SdAstNode         *m_arg;
                     SdAstCall(const string function_name, SdAstNode *period_expr)
                        : SdAstNode(SD_AST_CALL), m_name(function_name), m_arg(period_expr) {}
   virtual           ~SdAstCall() { if(m_arg != NULL) delete m_arg; }
  };

//+------------------------------------------------------------------+
class SdAstBands : public SdAstNode
  {
public:
   SdAstNode         *m_period;
   SdAstNode         *m_dev;
   int               m_member;
                     SdAstBands(SdAstNode *period_expr, SdAstNode *dev_expr, const int band_member)
                        : SdAstNode(SD_AST_BANDS), m_period(period_expr), m_dev(dev_expr), m_member(band_member) {}
   virtual           ~SdAstBands()
                       {
                        if(m_period != NULL) delete m_period;
                        if(m_dev != NULL)    delete m_dev;
                       }
  };

//+------------------------------------------------------------------+
class CSdParser
  {
private:
   CSdLexer          m_lexer;
   int               m_current_token;
   SdResult          m_internal_result;

   void              Advance();
   bool              Fail(const int code, const string detail);
   bool              Expect(const int expected_token, const string context_label);
   SdAstNode*        ParseExpr();
   SdAstNode*        ParseAdditive();
   SdAstNode*        ParseMult();
   SdAstNode*        ParseUnary();
   SdAstNode*        ParsePostfixable();
   SdAstNode*        ParseBandsExpression();
   SdAstNode*        ParseCorePrimary();
   SdAstNode*        ParseShiftSuffix(SdAstNode *inner_expr);
   bool              ParseSeriesName(const string identifier, int &series_kind_out);
   bool              IsFnOneArg(const string identifier) const;

public:
                     CSdParser(void) : m_current_token(SD_TOK_EOF) {}
   SdAstNode*        Parse(const string expression_text, SdResult &result_out);
  };

//+------------------------------------------------------------------+
void CSdParser::Advance()
  {
   m_current_token = m_lexer.Next();
  }

//+------------------------------------------------------------------+
bool CSdParser::Fail(const int code, const string detail)
  {
   string message = SdConfig_ErrorMessage(code);
   if(StringLen(detail) > 0)
      message = message + ": " + detail;
   SdResult_SetError(m_internal_result, code, message);
   return false;
  }

//+------------------------------------------------------------------+
bool CSdParser::Expect(const int expected_token, const string context_label)
  {
   if(m_current_token != expected_token)
     {
      Fail(SD_ERR_PARSE_EXPECTED, context_label);
      return false;
     }
   Advance();
   return true;
  }

//+------------------------------------------------------------------+
bool CSdParser::IsFnOneArg(const string identifier) const
  {
   if(StringCompare(identifier, "SMA") == 0)     return true;
   if(StringCompare(identifier, "EMA") == 0)     return true;
   if(StringCompare(identifier, "RSI") == 0)     return true;
   if(StringCompare(identifier, "ATR") == 0)     return true;
   if(StringCompare(identifier, "StdDev") == 0)  return true;
   return false;
  }

//+------------------------------------------------------------------+
bool CSdParser::ParseSeriesName(const string identifier, int &series_kind_out)
  {
   if(StringCompare(identifier, "Open") == 0)    { series_kind_out = SD_SER_OPEN;    return true; }
   if(StringCompare(identifier, "High") == 0)    { series_kind_out = SD_SER_HIGH;    return true; }
   if(StringCompare(identifier, "Low") == 0)     { series_kind_out = SD_SER_LOW;     return true; }
   if(StringCompare(identifier, "Close") == 0)  { series_kind_out = SD_SER_CLOSE;   return true; }
   if(StringCompare(identifier, "Volume") == 0)  { series_kind_out = SD_SER_VOLUME;  return true; }
   return false;
  }

//+------------------------------------------------------------------+
//| additive ::= mult (('+'|'-') mult)*                               |
//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseAdditive()
  {
   SdAstNode *expr = ParseMult();
   if(expr == NULL)
      return NULL;
   while(m_current_token == SD_TOK_PLUS || m_current_token == SD_TOK_MINUS)
     {
      const int op_char = (m_current_token == SD_TOK_PLUS) ? '+' : '-';
      Advance();
      SdAstNode *right_expr = ParseMult();
      if(right_expr == NULL)
        {
         delete expr;
         return NULL;
        }
      expr = new SdAstBinary(op_char, expr, right_expr);
     }
   return expr;
  }

//+------------------------------------------------------------------+
//| mult ::= unary (('*'|'/') unary)*                                |
//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseMult()
  {
   SdAstNode *expr = ParseUnary();
   if(expr == NULL)
      return NULL;
   while(m_current_token == SD_TOK_STAR || m_current_token == SD_TOK_SLASH)
     {
      const int op_char = (m_current_token == SD_TOK_STAR) ? '*' : '/';
      Advance();
      SdAstNode *right_expr = ParseUnary();
      if(right_expr == NULL)
        {
         delete expr;
         return NULL;
        }
      expr = new SdAstBinary(op_char, expr, right_expr);
     }
   return expr;
  }

//+------------------------------------------------------------------+
//| unary ::= '-' unary | postfixable                                |
//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseUnary()
  {
   if(m_current_token == SD_TOK_MINUS)
     {
      Advance();
      SdAstNode *child = ParseUnary();
      if(child == NULL)
         return NULL;
      return new SdAstUnaryMinus(child);
     }
   return ParsePostfixable();
  }

//+------------------------------------------------------------------+
//| Optional [ integer ] (single postfix; stacking not allowed).       |
//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseShiftSuffix(SdAstNode *inner_expr)
  {
   if(inner_expr == NULL)
      return NULL;
   if(m_current_token != SD_TOK_LBRACK)
      return inner_expr;
   Advance();
   if(m_current_token != SD_TOK_NUMBER)
     {
      Fail(SD_ERR_PARSE_EXPECTED, "[ expects integer");
      delete inner_expr;
      return NULL;
     }
   const double raw_shift = m_lexer.NumberValue();
   const int shift_int = (int)raw_shift;
   if((double)shift_int != raw_shift || shift_int < 0)
     {
      Fail(SD_ERR_PARSE_EXPECTED, "shift must be non-negative integer");
      delete inner_expr;
      return NULL;
     }
   Advance();
   if(!Expect(SD_TOK_RBRACK, "after shift"))
     {
      delete inner_expr;
      return NULL;
     }
   return new SdAstShift(inner_expr, shift_int);
  }

//+------------------------------------------------------------------+
//| Bands '(' expr ',' expr ')' '.' (Upper|Lower|Mid)                 |
//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseBandsExpression()
  {
   Advance();
   if(!Expect(SD_TOK_LPAREN, "Bands("))
      return NULL;
   SdAstNode *period_expr = ParseExpr();
   if(period_expr == NULL)
      return NULL;
   if(!Expect(SD_TOK_COMMA, "Bands( period ,"))
     {
      delete period_expr;
      return NULL;
     }
   SdAstNode *dev_expr = ParseExpr();
   if(dev_expr == NULL)
     {
      delete period_expr;
      return NULL;
     }
   if(!Expect(SD_TOK_RPAREN, "Bands )"))
     {
      delete period_expr;
      delete dev_expr;
      return NULL;
     }
   if(m_current_token != SD_TOK_DOT)
     {
      Fail(SD_ERR_PARSE_BARE_BANDS, "");
      delete period_expr;
      delete dev_expr;
      return NULL;
     }
   Advance();
   if(m_current_token != SD_TOK_IDENT)
     {
      Fail(SD_ERR_PARSE_BAD_BAND_MEMBER, "");
      delete period_expr;
      delete dev_expr;
      return NULL;
     }
   const string member_name = m_lexer.IdentText();
   int band_member = -1;
   if(StringCompare(member_name, "Upper") == 0)      band_member = SD_BAND_UPPER;
   else if(StringCompare(member_name, "Lower") == 0) band_member = SD_BAND_LOWER;
   else if(StringCompare(member_name, "Mid") == 0)   band_member = SD_BAND_MID;
   else
     {
      Fail(SD_ERR_PARSE_BAD_BAND_MEMBER, member_name);
      delete period_expr;
      delete dev_expr;
      return NULL;
     }
   Advance();
   return new SdAstBands(period_expr, dev_expr, band_member);
  }

//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseCorePrimary()
  {
   if(m_current_token == SD_TOK_NUMBER)
     {
      SdAstNode *num = new SdAstNumber(m_lexer.NumberValue());
      Advance();
      return num;
     }

   if(m_current_token == SD_TOK_LPAREN)
     {
      Advance();
      SdAstNode *grouped = ParseExpr();
      if(grouped == NULL)
         return NULL;
      if(!Expect(SD_TOK_RPAREN, "group"))
        {
         delete grouped;
         return NULL;
        }
      return grouped;
     }

   if(m_current_token == SD_TOK_IDENT)
     {
      const string identifier = m_lexer.IdentText();
      Advance();
      if(m_current_token == SD_TOK_LPAREN)
        {
         if(!IsFnOneArg(identifier))
           {
            Fail(SD_ERR_PARSE_UNKNOWN_FUNC, identifier);
            return NULL;
           }
         Advance();
         SdAstNode *arg_expr = ParseExpr();
         if(arg_expr == NULL)
            return NULL;
         if(!Expect(SD_TOK_RPAREN, "closing )"))
           {
            delete arg_expr;
            return NULL;
           }
         return new SdAstCall(identifier, arg_expr);
        }
      int series_kind = 0;
      if(ParseSeriesName(identifier, series_kind))
         return new SdAstSeries(series_kind);
      Fail(SD_ERR_PARSE_UNKNOWN_IDENT, identifier);
      return NULL;
     }

   Fail(SD_ERR_PARSE_EXPECTED, "value or (");
   return NULL;
  }

//+------------------------------------------------------------------+
//| postfixable ::= bands_expr postfix? | core_primary postfix?       |
//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParsePostfixable()
  {
   SdAstNode *base_expr = NULL;
   if(m_current_token == SD_TOK_IDENT && StringCompare(m_lexer.IdentText(), "Bands") == 0)
      base_expr = ParseBandsExpression();
   else
      base_expr = ParseCorePrimary();
   if(base_expr == NULL)
      return NULL;
   return ParseShiftSuffix(base_expr);
  }

//+------------------------------------------------------------------+
SdAstNode* CSdParser::ParseExpr()
  {
   return ParseAdditive();
  }

//+------------------------------------------------------------------+
SdAstNode* CSdParser::Parse(const string expression_text, SdResult &result_out)
  {
   SdResult_Clear(m_internal_result);
   SdResult_Clear(result_out);
   string trimmed = expression_text;
   StringTrimLeft(trimmed);
   StringTrimRight(trimmed);
   if(StringLen(trimmed) == 0)
     {
      Fail(SD_ERR_PARSE_EMPTY_EXPR, "");
      result_out = m_internal_result;
      return NULL;
     }
   m_lexer.Init(trimmed);
   Advance();
   if(m_current_token == SD_TOK_INVALID)
     {
      Fail(SD_ERR_LEX_UNEXPECTED, "");
      result_out = m_internal_result;
      return NULL;
     }
   SdAstNode *root = ParseExpr();
   if(root == NULL)
     {
      result_out = m_internal_result;
      return NULL;
     }
   if(m_current_token != SD_TOK_EOF)
     {
      Fail(SD_ERR_PARSE_EXPECTED, "trailing input");
      delete root;
      result_out = m_internal_result;
      return NULL;
     }
   SdResult_SetOk(m_internal_result);
   result_out = m_internal_result;
   return root;
  }

//+------------------------------------------------------------------+
void SdAst_Free(SdAstNode *root)
  {
   if(root == NULL)
      return;
   delete root;
  }

#endif
