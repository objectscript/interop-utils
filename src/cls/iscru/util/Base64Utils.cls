/// Container for helper methods for Base64 (en-/de-)coding.
Class iscru.util.Base64Utils [ Abstract ]
{

/// Base64 encoding of a binary value. 
/// The lineTerminator argument specifies the line separator in the resulting Base64 stream; by default, $char(10).
ClassMethod encodeBinaryStream(binaryStream As %Stream.Object, Output base64Stream As %Stream.TmpCharacter, lineTerminator As %String = {$char(10)}) As %Status
{
	set base64Stream = ##class(%Stream.TmpCharacter).%New()
	
	#dim sc As %Status = ..encodeInternal(binaryStream, base64Stream, lineTerminator)
	if $$$ISERR(sc) quit sc
	
	do base64Stream.Rewind()
	quit $$$OK
}

/// Base64 encoding of text. 
/// The lineTerminator argument specifies the line separator in the resulting Base64 stream; the default is $char(10).
/// The encoding argument specifies the value used in the $zconvert() call to transform strings into byte arrays; the default is UTF8.
ClassMethod encodeCharacterStream(characterStream As %Stream.Object, Output base64Stream As %Stream.TmpCharacter, lineTerminator As %String = {$char(10)}, encoding As %String = "UTF8") As %Status
{
	set base64Stream = ##class(%Stream.TmpCharacter).%New()
	
	#dim sc As %Status = ..encodeInternal(characterStream, base64Stream, lineTerminator, encoding)
	if $$$ISERR(sc) quit sc
	
	do base64Stream.Rewind()
	quit $$$OK
}

/// Base64 encoding.
/// The $SYSTEM.Encryption.Base64Encode() method only accepts input strings where each character occupies one byte.
/// Therefore, when encoding character streams, the zconv argument is expected to be "UTF8", "CP1251" or another single-byte encoding.
ClassMethod encodeInternal(inputStream As %Stream.Object, base64Stream As %Stream.Object, lineTerminator As %String, zconv As %String = "") As %Status [ Private ]
{
	#dim sc As %Status = $$$OK
	#dim len As %Integer
	#dim encodedline As %String
	#dim decodedline As %String
	#dim convertedStream As %Stream.Object
	
	if (zconv '= "")
	{
		// In addition to the conversion method below, there is another one:
		//   $ZConvert(str, "O", "UTF8") converts a regular string (UTF-16) into a single-byte character string (UTF-8); you can verify this using zzdump.
		
		do inputStream.Rewind()
		set convertedStream = ##class(%FileCharacterStream).%New()
		set convertedStream.TranslateTable = zconv
		do convertedStream.CopyFrom(inputStream)
		set convertedStream.TranslateTable = "RAW"
	}
	else
	{
		set convertedStream = inputStream
	}

	do convertedStream.Rewind()
	while 'convertedStream.AtEnd
	{
		set len = 1026  // must be divisible by 3 and 57!!!
		set decodedline = convertedStream.Read(.len, .sc)
		if $$$ISERR(sc) quit
		
		try
		{
			set encodedline = $system.Encryption.Base64Encode(decodedline)
		}
		catch ex
		{
			set sc = ex.AsStatus()
		}
		
		if $$$ISERR(sc) quit
		
		// if the line terminator is Unix-style, remove all $char(13) characters
		if (lineTerminator = $c(10)) set encodedline = $translate(encodedline, $c(13))
		
		do base64Stream.Write(encodedline)
		do base64Stream.Write(lineTerminator)
	}

	quit sc
}

/// Base64 decoding of a binary value. 
/// The lineTerminator argument is retained for compatibility with legacy code.
ClassMethod decodeToBinaryStream(base64Stream As %Stream.Object, Output result As %Stream.TmpBinary, lineTerminator As %String = {$c(10)}) As %Status
{
	set result = ##class(%Stream.TmpBinary).%New()
	
	#dim sc As %Status = ..decodeInternal(base64Stream, result)
	if $$$ISERR(sc) quit sc
	
	do result.Rewind()
	quit $$$OK
}

/// Base64 decoding of text. 
/// The lineTerminator argument is retained for compatibility with legacy code.
/// The encoding argument specifies the value used to convert the byte array (RAW) into a character stream; the default is UTF8.
ClassMethod decodeToCharacterStream(base64Stream As %Stream.Object, Output result As %CharacterStream, lineTerminator As %String = {$c(10)}, encoding As %String = "UTF8") As %Status
{
	set result = ##class(%FileCharacterStream).%New()
	set result.TranslateTable = "RAW"
	
	#dim sc As %Status = ..decodeInternal(base64Stream, result)
	if $$$ISERR(sc) quit sc
	
	set result.TranslateTable = encoding
	do result.Rewind()
	quit $$$OK
}

ClassMethod decodeInternal(base64Stream As %Stream.Object, result As %Stream.Object) As %Status [ Private ]
{
	#dim sc As %Status = $$$OK
	
	do base64Stream.Rewind()
	
	#dim leftOver As %String = ""
	while 'base64Stream.AtEnd
	{ 
		#dim decodedline As %String
		try
		{
			#dim encoded As %String = base64Stream.Read($$$MaxLocalLength - 4, .sc)
			if $$$ISERR(sc) quit
			
			set encoded = leftOver _ $tr(encoded, $c(13, 10, 32, 9))
			
			#dim pos As %Integer = $length(encoded) - ($length(encoded) # 4)
			set leftOver = $e(encoded, pos + 1, *)
			set encoded = $e(encoded, 1, pos)
			
			set decodedline = $system.Encryption.Base64Decode(encoded)
		}
		catch ex
		{
			set sc = ex.AsStatus()
		}
		if $$$ISERR(sc) quit
		
		do result.Write(decodedline)
	}

	quit sc
}

ClassMethod decodeFile(inFileName As %String, outFileName As %String) As %Status
{
	#dim sc As %Status
	
	#dim in As %FileBinaryStream = ##class(%FileBinaryStream).%New()
	set sc = in.LinkToFile(inFileName)
	if $$$ISERR(sc) quit sc
	
	if in.%IsNull() quit $$$ERROR($$$GeneralError, "File not found: " _ inFileName)
	
	#dim out As %FileBinaryStream = ##class(%FileBinaryStream).%New()
	set sc = out.LinkToFile(outFileName)
	if $$$ISERR(sc) quit sc
	
	do out.Clear()
	
	#dim result As %Stream.Object
	set sc = ..decodeToBinaryStream(in, .result)
	if $$$ISERR(sc) quit sc
	
	quit out.CopyFromAndSave(result)
}

ClassMethod encodeFile(inFileName As %String, outFileName As %String) As %Status
{
	#dim sc As %Status
	
	#dim in As %FileCharacterStream = ##class(%FileCharacterStream).%New()
	set in.TranslateTable = "UTF8"
	set sc = in.LinkToFile(inFileName)
	if $$$ISERR(sc) quit sc
	
	if in.%IsNull() quit $$$ERROR($$$GeneralError, "File not found: " _ inFileName)
	
	#dim out As %FileBinaryStream = ##class(%FileBinaryStream).%New()
	set sc = out.LinkToFile(outFileName)
	if $$$ISERR(sc) quit sc
	
	do out.Clear()
	
	set sc = ..encodeInternal(in, out, $c(10), "UTF8")
	if $$$ISERR(sc) quit sc
	
	quit out.%Save()
}

}

