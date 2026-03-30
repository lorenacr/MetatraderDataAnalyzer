//+------------------------------------------------------------------+
//| SD_ExprLexer.mqh                                                 |
//| Scans expression text into tokens.                               |
//| After Next(), PeekType / NumberValue / IdentText read the token.  |
//+------------------------------------------------------------------+
#ifndef __SD_EXPR_LEXER_MQH__
#define __SD_EXPR_LEXER_MQH__

// Token kinds produced by CSdLexer::Next().
enum ENUM_SD_TOK
  {
   SD_TOK_EOF = 0,
   SD_TOK_NUMBER,
   SD_TOK_IDENT,
   SD_TOK_PLUS,
   SD_TOK_MINUS,
   SD_TOK_STAR,
   SD_TOK_SLASH,
   SD_TOK_LPAREN,
   SD_TOK_RPAREN,
   SD_TOK_COMMA,
   SD_TOK_LBRACK,
   SD_TOK_RBRACK,
   SD_TOK_DOT,
   SD_TOK_INVALID
  };

//+------------------------------------------------------------------+
//| UTF-16 scanner: one code unit at a time, no lexer lookahead obj. |
//+------------------------------------------------------------------+
class CSdLexer
  {
private:
   string            m_source_text;
   int               m_cursor;
   int               m_source_length;
   int               m_current_token_kind;
   double            m_number_value;
   string            m_identifier_text;

   bool              IsSpace(const ushort ch) const;
   bool              IsDigit(const ushort ch) const;
   bool              IsIdentStart(const ushort ch) const;
   bool              IsIdentCont(const ushort ch) const;
   ushort            CurrentCodeUnit() const;
   void              AdvanceCursor();

public:
                     CSdLexer(void);
   void              Init(const string source_text);
   int               Next();
   int               PeekType() const { return m_current_token_kind; }
   double            NumberValue() const { return m_number_value; }
   string            IdentText() const { return m_identifier_text; }
   int               Position() const { return m_cursor; }
  };

//+------------------------------------------------------------------+
CSdLexer::CSdLexer(void)
   : m_cursor(0),
     m_source_length(0),
     m_current_token_kind(SD_TOK_EOF),
     m_number_value(0.0),
     m_identifier_text("")
  {
   m_source_text = "";
  }

//+------------------------------------------------------------------+
void CSdLexer::Init(const string source_text)
  {
   m_source_text = source_text;
   m_source_length = StringLen(m_source_text);
   m_cursor = 0;
   m_current_token_kind = SD_TOK_EOF;
   m_number_value = 0.0;
   m_identifier_text = "";
  }

//+------------------------------------------------------------------+
bool CSdLexer::IsSpace(const ushort ch) const
  {
   return (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n');
  }

//+------------------------------------------------------------------+
bool CSdLexer::IsDigit(const ushort ch) const
  {
   return (ch >= '0' && ch <= '9');
  }

//+------------------------------------------------------------------+
bool CSdLexer::IsIdentStart(const ushort ch) const
  {
   return ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_');
  }

//+------------------------------------------------------------------+
bool CSdLexer::IsIdentCont(const ushort ch) const
  {
   return (IsIdentStart(ch) || IsDigit(ch));
  }

//+------------------------------------------------------------------+
ushort CSdLexer::CurrentCodeUnit() const
  {
   if(m_cursor >= m_source_length)
      return 0;
   return (ushort)StringGetCharacter(m_source_text, m_cursor);
  }

//+------------------------------------------------------------------+
void CSdLexer::AdvanceCursor()
  {
   if(m_cursor < m_source_length)
      m_cursor++;
  }

//+------------------------------------------------------------------+
//| Skip spaces, then classify next token into member fields.         |
//| Illegal character → SD_TOK_INVALID (caller maps to lex error).    |
//+------------------------------------------------------------------+
int CSdLexer::Next()
  {
   while(m_cursor < m_source_length && IsSpace(CurrentCodeUnit()))
      AdvanceCursor();

   if(m_cursor >= m_source_length)
     {
      m_current_token_kind = SD_TOK_EOF;
      return m_current_token_kind;
     }

   const ushort current = CurrentCodeUnit();

   if(IsDigit(current) ||
      (current == '.' && m_cursor + 1 < m_source_length &&
       IsDigit((ushort)StringGetCharacter(m_source_text, m_cursor + 1))))
     {
      const int lexeme_start = m_cursor;
      bool has_decimal_point = false;
      if(current == '.')
        {
         has_decimal_point = true;
         AdvanceCursor();
        }
      while(m_cursor < m_source_length && IsDigit(CurrentCodeUnit()))
         AdvanceCursor();
      if(!has_decimal_point && m_cursor < m_source_length && CurrentCodeUnit() == '.')
        {
         has_decimal_point = true;
         AdvanceCursor();
         while(m_cursor < m_source_length && IsDigit(CurrentCodeUnit()))
            AdvanceCursor();
        }
      const string number_lexeme = StringSubstr(m_source_text, lexeme_start, m_cursor - lexeme_start);
      m_number_value = StringToDouble(number_lexeme);
      m_current_token_kind = SD_TOK_NUMBER;
      return m_current_token_kind;
     }

   if(IsIdentStart(current))
     {
      const int lexeme_start = m_cursor;
      while(m_cursor < m_source_length && IsIdentCont(CurrentCodeUnit()))
         AdvanceCursor();
      m_identifier_text = StringSubstr(m_source_text, lexeme_start, m_cursor - lexeme_start);
      m_current_token_kind = SD_TOK_IDENT;
      return m_current_token_kind;
     }

   AdvanceCursor();
   switch(current)
     {
      case '+':
         m_current_token_kind = SD_TOK_PLUS;
         break;
      case '-':
         m_current_token_kind = SD_TOK_MINUS;
         break;
      case '*':
         m_current_token_kind = SD_TOK_STAR;
         break;
      case '/':
         m_current_token_kind = SD_TOK_SLASH;
         break;
      case '(':
         m_current_token_kind = SD_TOK_LPAREN;
         break;
      case ')':
         m_current_token_kind = SD_TOK_RPAREN;
         break;
      case ',':
         m_current_token_kind = SD_TOK_COMMA;
         break;
      case '[':
         m_current_token_kind = SD_TOK_LBRACK;
         break;
      case ']':
         m_current_token_kind = SD_TOK_RBRACK;
         break;
      case '.':
         m_current_token_kind = SD_TOK_DOT;
         break;
      default:
         m_current_token_kind = SD_TOK_INVALID;
         break;
     }
   return m_current_token_kind;
  }

#endif
