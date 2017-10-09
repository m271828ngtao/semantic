{-# LANGUAGE DataKinds, DeriveAnyClass, RankNTypes, TypeOperators #-}
module Language.Go.Syntax
( assignment
, Syntax
, Grammar
, Term
) where

import Data.Functor (void)
import Data.List.NonEmpty (some1)
import Data.Record
import Data.Syntax (contextualize, postContextualize, emptyTerm, parseError, handleError, infixContext, makeTerm, makeTerm', makeTerm1)
import qualified Data.Syntax as Syntax
import Data.Syntax.Assignment hiding (Assignment, Error)
import qualified Data.Syntax.Assignment as Assignment
import qualified Data.Syntax.Comment as Comment
import qualified Data.Syntax.Declaration as Declaration
import qualified Data.Syntax.Expression as Expression
import qualified Data.Syntax.Literal as Literal
import qualified Data.Syntax.Statement as Statement
import qualified Data.Syntax.Type as Type
import qualified Data.Term as Term
import Data.Union
import GHC.Stack
import Language.Go.Grammar as Grammar

type Syntax =
  '[ Comment.Comment
   , Declaration.Constructor
   , Declaration.Function
   , Declaration.Import
   , Declaration.Interface
   , Declaration.Method
   , Declaration.Module
   , Expression.Arithmetic
   , Expression.Bitwise
   , Expression.Boolean
   , Expression.Call
   , Expression.Comparison
   , Expression.MemberAccess
   , Literal.Array
   , Literal.Channel
   , Literal.Composite
   , Literal.Hash
   , Literal.Integer
   , Literal.KeyValue
   , Literal.TextElement
   , Statement.Assignment
   , Statement.Break
   , Statement.Return
   , Syntax.Context
   , Syntax.Error
   , Syntax.Empty
   , Syntax.Identifier
   , Syntax.Program
   , Type.Annotation
   , Type.Array
   , Type.BiDirectionalChannel
   , Type.Function
   , Type.Interface
   , Type.Map
   , Type.Pointer
   , Type.ReceiveChannel
   , Type.SendChannel
   , Type.Slice
   , []
   ]

type Term = Term.Term (Union Syntax) (Record Location)
type Assignment = HasCallStack => Assignment.Assignment [] Grammar Term

-- | Assignment from AST in Go's grammar onto a program in Go's syntax.
assignment :: Assignment
assignment = handleError $ makeTerm <$> symbol SourceFile <*> children (Syntax.Program <$> many expression) <|> parseError

expression :: Assignment
expression = term (handleError (choice expressionChoices))

expressionChoices :: [Assignment.Assignment [] Grammar Term]
expressionChoices =
  [ binaryExpression
  , breakStatement
  , callExpression
  , channelType
  , comment
  , compositeLiteral
  , constVarDeclaration
  , constVarSpecification
  , element
  , expressionList
  , fieldDeclaration
  , fieldIdentifier
  , functionDeclaration
  , functionType
  , identifier
  , implicitLengthArrayType
  , importDeclaration
  , importSpec
  , interfaceType
  , interpretedStringLiteral
  , intLiteral
  , literalValue
  , mapType
  , methodDeclaration
  , methodSpec
  , packageClause
  , packageIdentifier
  , parameterDeclaration
  , parenthesizedType
  , pointerType
  , rawStringLiteral
  , returnStatement
  , sliceType
  , structType
  , typeDeclaration
  , typeIdentifier
  ]

identifiers :: Assignment
identifiers = mk <$> location <*> many identifier
  where mk _ [a] = a
        mk loc children = makeTerm loc children

expressions :: Assignment
expressions = mk <$> location <*> many expression
  where mk _ [a] = a
        mk loc children = makeTerm loc children


-- Literals

element :: Assignment
element = symbol Element *> children expression

literalValue :: Assignment
literalValue = makeTerm <$> symbol LiteralValue <*> children (many expression)

compositeLiteral :: Assignment
compositeLiteral = makeTerm <$> symbol CompositeLiteral <*> children (Literal.Composite <$> expression <*> expression)

intLiteral :: Assignment
intLiteral = makeTerm <$> symbol IntLiteral <*> (Literal.Integer <$> source)

rawStringLiteral :: Assignment
rawStringLiteral = makeTerm <$> symbol RawStringLiteral <*> (Literal.TextElement <$> source)

typeIdentifier :: Assignment
typeIdentifier = makeTerm <$> symbol TypeIdentifier <*> (Syntax.Identifier <$> source)

identifier :: Assignment
identifier =  makeTerm <$> symbol Identifier <*> (Syntax.Identifier <$> source)

fieldIdentifier :: Assignment
fieldIdentifier = makeTerm <$> symbol FieldIdentifier <*> (Syntax.Identifier <$> source)

packageIdentifier :: Assignment
packageIdentifier = makeTerm <$> symbol PackageIdentifier <*> (Syntax.Identifier <$> source)

parenthesizedType :: Assignment
parenthesizedType = makeTerm <$> symbol ParenthesizedType <*> (Syntax.Identifier <$> source)

interpretedStringLiteral :: Assignment
interpretedStringLiteral = makeTerm <$> symbol InterpretedStringLiteral <*> (Literal.TextElement <$> source)

comment :: Assignment
comment = makeTerm <$> symbol Comment <*> (Comment.Comment <$> source)


-- Primitive Types

qualifiedType :: Assignment
qualifiedType = makeTerm <$> symbol QualifiedType <*> children (Expression.MemberAccess <$> expression <*> expression)

arrayType :: Assignment
arrayType = makeTerm <$> symbol ArrayType <*> children (Type.Array . Just <$> expression <*> expression)

implicitLengthArrayType :: Assignment
implicitLengthArrayType = makeTerm <$> symbol ImplicitLengthArrayType <*> children (Type.Array Nothing <$> expression)

functionType :: Assignment
functionType = makeTerm <$> symbol FunctionType <*> children (Type.Function <$> parameters <*> returnType)
  where parameters = symbol Parameters *> children (many expression)
        returnType = symbol Parameters *> children expressions <|> expression <|> emptyTerm

sliceType :: Assignment
sliceType = makeTerm <$> symbol SliceType <*> children (Type.Slice <$> expression)

channelType :: Assignment
channelType = handleError
            $  (makeTerm <$> symbol ChannelType <*> (children (token AnonLAngleMinus *> token AnonChan *> (Type.ReceiveChannel <$> expression))))
           <|> (makeTerm <$> symbol ChannelType <*> (children (token AnonChan *> token AnonLAngleMinus *> (Type.SendChannel <$> expression))))
           <|> (makeTerm <$> symbol ChannelType <*> (children (token AnonChan *>                          (Type.BiDirectionalChannel <$> expression))))

structType :: Assignment
structType = handleError $ makeTerm <$> symbol StructType <*> children (Declaration.Constructor <$> emptyTerm <*> many expression)

interfaceType :: Assignment
interfaceType = handleError $ makeTerm <$> symbol InterfaceType <*> children (Type.Interface <$> many expression)

mapType :: Assignment
mapType = handleError $ makeTerm <$> symbol MapType <*> children (Type.Map <$> expression <*> expression)

pointerType :: Assignment
pointerType = handleError $ makeTerm <$> symbol PointerType <*> children (Type.Pointer <$> expression)

fieldDeclaration :: Assignment
fieldDeclaration =  mkFieldDeclarationWithTag <$> symbol FieldDeclaration <*> children ((,,) <$> many identifier <*> expression <*> optional expression)
  where
        mkFieldDeclarationWithTag loc (fields, type', (Just tag)) = makeTerm loc $ Type.Annotation (makeTerm loc (Type.Annotation (makeTerm loc fields) type')) tag
        mkFieldDeclarationWithTag loc (fields, type', Nothing) = makeTerm loc $ Type.Annotation (makeTerm loc fields) type'

-- Type Declarations

channelTypeDeclaration :: Assignment
channelTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> channelType)

functionTypeDeclaration :: Assignment
functionTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> functionType)

interfaceTypeDeclaration :: Assignment
interfaceTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> interfaceType)

mapTypeDeclaration :: Assignment
mapTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> mapType)

structTypeDeclaration :: Assignment
structTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> structType)

qualifiedTypeDeclaration :: Assignment
qualifiedTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> qualifiedType)

arrayTypeDeclaration :: Assignment
arrayTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> arrayType)

sliceTypeDeclaration :: Assignment
sliceTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> sliceType)

pointerTypeDeclaration :: Assignment
pointerTypeDeclaration = makeTerm <$> symbol TypeSpec <*> children (Type.Annotation <$> typeIdentifier <*> pointerType)

typeDeclaration :: Assignment
typeDeclaration = handleError $ makeTerm <$> symbol TypeDeclaration <*> children (many ( arrayTypeDeclaration
                                                                                      <|> channelTypeDeclaration
                                                                                      <|> functionTypeDeclaration
                                                                                      <|> interfaceTypeDeclaration
                                                                                      <|> qualifiedTypeDeclaration
                                                                                      <|> pointerTypeDeclaration
                                                                                      <|> sliceTypeDeclaration
                                                                                      <|> structTypeDeclaration
                                                                                      <|> mapTypeDeclaration ))


-- Expressions

binaryExpression :: Assignment
binaryExpression = makeTerm' <$> symbol BinaryExpression <*> children (infixTerm expression expression
  [ (inj .) . Expression.Plus             <$ symbol AnonPlus
  , (inj .) . Expression.Minus            <$ symbol AnonMinus
  , (inj .) . Expression.Times            <$ symbol AnonStar
  , (inj .) . Expression.DividedBy        <$ symbol AnonSlash
  , (inj .) . Expression.Modulo           <$ symbol AnonPercent
  , (inj .) . Expression.Or               <$ symbol AnonPipePipe
  , (inj .) . Expression.And              <$ symbol AnonAmpersandAmpersand
  , (inj .) . Expression.BOr              <$ symbol AnonPipe
  , (inj .) . Expression.BAnd             <$ symbol AnonAmpersand
  , (inj .) . Expression.BAnd             <$ symbol AnonAmpersandCaret
  , (inj .) . Expression.BXOr             <$ symbol AnonCaret
  , (inj .) . Expression.LShift           <$ symbol AnonLAngleLAngle
  , (inj .) . Expression.RShift           <$ symbol AnonRAngleRAngle
  , (inj .) . Expression.LessThan         <$ symbol AnonLAngle
  , (inj .) . Expression.LessThanEqual    <$ symbol AnonLAngleEqual
  , (inj .) . Expression.GreaterThan      <$ symbol AnonRAngle
  , (inj .) . Expression.GreaterThanEqual <$ symbol AnonRAngleEqual
  , (inj .) . Expression.Equal            <$ symbol AnonEqualEqual
  , (inj .) . invert Expression.Equal     <$ symbol AnonBangEqual
  ])
  where invert cons a b = Expression.Not (makeTerm1 (cons a b))

block :: Assignment
block = symbol Block *> children expressions

callExpression :: Assignment
callExpression = makeTerm <$> symbol CallExpression <*> children (Expression.Call <$> pure [] <*> identifier <*> pure [] <*> emptyTerm)

constVarDeclaration :: Assignment
constVarDeclaration = (symbol ConstDeclaration <|> symbol VarDeclaration) *> children expressions

constVarSpecification :: Assignment
constVarSpecification = makeTerm <$> (symbol ConstSpec <|> symbol VarSpec) <*> children (Statement.Assignment
                                                                           <$> pure []
                                                                           <*> (annotatedLHS <|> identifiers)
                                                                           <*> expressions)
    where
      annotatedLHS = makeTerm <$> location <*> (Type.Annotation
                                              <$> (makeTerm <$> location <*> (manyTermsTill identifier (void (symbol TypeIdentifier))))
                                              <*> expression)

expressionList :: Assignment
expressionList = symbol ExpressionList *> children expressions

functionDeclaration :: Assignment
functionDeclaration = mkTypedFunctionDeclaration <$> symbol FunctionDeclaration <*> children ((,,,) <$> expression <*> parameters <*> (expression <|> emptyTerm) <*> block)
  where mkTypedFunctionDeclaration loc (name', params', types', block') = makeTerm loc (Declaration.Function [types'] name' params' block')
        parameters = symbol Parameters *> children (many expression)

importDeclaration :: Assignment
importDeclaration = makeTerm <$> symbol ImportDeclaration <*> children (Declaration.Import <$> many expression)

importSpec :: Assignment
importSpec = symbol ImportSpec *> children expressions

methodDeclaration :: Assignment
methodDeclaration = mkTypedMethodDeclaration <$> symbol MethodDeclaration <*> children ((,,,,) <$> receiver <*> fieldIdentifier <*> parameters <*> typeIdentifier <*> block)
  where parameters = symbol Parameters *> children (symbol ParameterDeclaration *> children (many expression))
        receiver = symbol Parameters *> children (symbol ParameterDeclaration *> children expressions)
        mkTypedMethodDeclaration loc (receiver', name', parameters', type'', body') = makeTerm loc (Declaration.Method [type''] receiver' name' parameters' body')

methodSpec :: Assignment
methodSpec =  mkMethodSpec <$> symbol MethodSpec <*> children ((,,,,) <$> empty <*> identifier <*> parameters <*> (expression <|> parameters <|> emptyTerm) <*> empty)
  where parameters = makeTerm <$> symbol Parameters <*> children (many expression)
        empty = makeTerm <$> location <*> pure Syntax.Empty
        mkMethodSpec loc (receiver', name', params, optionaltypeLiteral, body') = makeTerm loc $ Type.Annotation (mkMethod loc receiver' name' params body') optionaltypeLiteral
        mkMethod loc empty' name' params empty'' = makeTerm loc $ Declaration.Method [] empty' name' (pure params) empty''

packageClause :: Assignment
packageClause = makeTerm <$> symbol PackageClause <*> children (Declaration.Module <$> expression <*> pure [])

parameterDeclaration :: Assignment
parameterDeclaration = symbol ParameterDeclaration *> children expressions


-- Statements

breakStatement :: Assignment
breakStatement = makeTerm <$> symbol BreakStatement <*> children (Statement.Break <$> labelName)

labelName :: Assignment
labelName = makeTerm <$> symbol LabelName <*> (Syntax.Identifier <$> source)

returnStatement :: Assignment
returnStatement = makeTerm <$> symbol ReturnStatement <*> children (Statement.Return <$> (expression <|> emptyTerm))

-- Helpers

-- | Match infix terms separated by any of a list of operators, assigning any comments following each operand.
infixTerm :: HasCallStack
          => Assignment
          -> Assignment
          -> [Assignment.Assignment [] Grammar (Term -> Term -> Union Syntax Term)]
          -> Assignment.Assignment [] Grammar (Union Syntax Term)
infixTerm = infixContext comment

-- | Match a term optionally preceded by comment(s), or a sequence of comments if the term is not present.
term :: Assignment -> Assignment
term term = contextualize comment term <|> makeTerm1 <$> (Syntax.Context <$> some1 comment <*> emptyTerm)

-- | Match a series of terms or comments until a delimiter is matched
manyTermsTill :: Show b => Assignment.Assignment [] Grammar Term -> Assignment.Assignment [] Grammar b -> Assignment.Assignment [] Grammar [Term]
manyTermsTill step end = manyTill (step <|> comment) end
