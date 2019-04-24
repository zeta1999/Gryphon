/*
* Copyright 2018 Vinícius Jorge Vendramini
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import Foundation

public class Compiler {
	static let kotlinCompilerPath = (OS.osName == "Linux") ?
		"/opt/kotlinc/bin/kotlinc" :
		"/usr/local/bin/kotlinc"

	//
	public private(set) static var log: ((String) -> ()) = { print($0) }

	public static func shouldLogProgress(if value: Bool) {
		if value {
			log = { print($0) }
		}
		else {
			log = { _ in }
		}
	}

	//
	public static var shouldStopAtFirstError = false

	public private(set) static var errors: ArrayClass<Error> = []
	public private(set) static var warnings: ArrayClass<String> = []

	internal static func handleError(_ error: Error) throws {
		if Compiler.shouldStopAtFirstError {
			throw error
		}
		else {
			Compiler.errors.append(error)
		}
	}

	public static func clearErrorsAndWarnings() {
		errors = []
		warnings = []
	}

	//
	public static func generateSwiftAST(fromASTDump astDump: String) throws -> SwiftAST {
		log("\t- Building SwiftAST...")
		let ast = try ASTDumpDecoder(encodedString: astDump).decode()
		return ast
	}

	public static func transpileSwiftAST(fromASTDumpFile inputFile: String) throws -> SwiftAST {
		let astDump = try Utilities.readFile(inputFile)
		return try generateSwiftAST(fromASTDump: astDump)
	}
}

extension Compiler { // kotlin: ignore
	public static func runCompiledProgram(
		fromFolder outputFolder: String,
		withArguments arguments: [String] = [])
		throws -> Shell.CommandOutput?
	{
		log("\t- Running Kotlin...")
		let commandArguments = ["java", "-jar", "kotlin.jar"] + arguments
		let commandResult = Shell.runShellCommand(commandArguments, fromFolder: outputFolder)

		return commandResult
	}

	public static func compile(kotlinFiles filePaths: [String], outputFolder: String)
		throws -> Shell.CommandOutput?
	{
		log("\t- Compiling Kotlin...")

		// Call the kotlin compiler
		let arguments = ["-include-runtime", "-d", outputFolder + "/kotlin.jar"] + filePaths
		let commandResult = Shell.runShellCommand(kotlinCompilerPath, arguments: arguments)

		return commandResult
	}

	public static func generateKotlinCode(fromGryphonAST ast: GryphonAST) throws -> String {
		log("\t- Translating AST to Kotlin...")
		return try KotlinTranslator().translateAST(ast)
	}

	public static func generateGryphonAST(fromGryphonRawAST ast: GryphonAST) throws -> GryphonAST {
		var ast = ast
		log("\t- Running passes on Gryphon ASTs...")
		try Utilities.updateLibraryFiles()
		ast = TranspilationPass.runFirstRoundOfPasses(on: ast)
		ast = TranspilationPass.runSecondRoundOfPasses(on: ast)
		return ast
	}

	public static func generateGryphonASTAfterSecondPasses(fromGryphonRawAST ast: GryphonAST)
		throws -> GryphonAST
	{
		log("\t- Running second round of passes...")
		try Utilities.updateLibraryFiles()
		return TranspilationPass.runSecondRoundOfPasses(on: ast)
	}

	public static func generateGryphonASTAfterFirstPasses(fromGryphonRawAST ast: GryphonAST)
		throws -> GryphonAST
	{
		log("\t- Running first round of passes...")
		try Utilities.updateLibraryFiles()
		return TranspilationPass.runFirstRoundOfPasses(on: ast)
	}

	public static func generateGryphonRawAST(fromSwiftAST swiftAST: SwiftAST, asMainFile: Bool)
		throws -> GryphonAST
	{
		log("\t- Translating Swift ASTs to Gryphon ASTs...")
		return try SwiftTranslator().translateAST(swiftAST, asMainFile: asMainFile)
	}

	//
	public static func transpileCompileAndRun(
		ASTDumpFiles inputFiles: [String], fromFolder outputFolder: String = OS.buildFolder)
		throws -> Shell.CommandOutput?
	{
		let compilationResult =
			try transpileThenCompile(ASTDumpFiles: inputFiles, outputFolder: outputFolder)
		guard compilationResult != nil, compilationResult!.status == 0 else {
			return compilationResult
		}
		return try runCompiledProgram(fromFolder: outputFolder)
	}

	public static func transpileThenCompile(
		ASTDumpFiles inputFiles: [String], outputFolder: String = OS.buildFolder)
		throws -> Shell.CommandOutput?
	{
		let kotlinCodes = try transpileKotlinCode(fromASTDumpFiles: inputFiles)
		// Write kotlin files to the output folder
		let kotlinFilePaths = zip(inputFiles, kotlinCodes).map { tuple -> String in
			let inputFile = tuple.0
			let kotlinCode = tuple.1
			let inputFileName = inputFile.split(withStringSeparator: "/").last!
			let kotlinFileName = Utilities.changeExtension(of: inputFileName, to: .kt)
			let folderWithSlash = outputFolder.hasSuffix("/") ? outputFolder : (outputFolder + "/")
			let kotlinFilePath = folderWithSlash + kotlinFileName
			Utilities.createFile(atPath: kotlinFilePath, containing: kotlinCode)
			return kotlinFilePath
		}
		return try compile(kotlinFiles: kotlinFilePaths, outputFolder: outputFolder)
	}

	public static func transpileKotlinCode(fromASTDumpFiles inputFiles: [String]) throws -> [String]
	{
		let asts = try transpileGryphonASTs(fromASTDumpFiles: inputFiles)
		return try asts.map { try generateKotlinCode(fromGryphonAST: $0) }
	}

	public static func transpileGryphonASTs(fromASTDumpFiles inputFiles: [String])
		throws -> [GryphonAST]
	{
		let rawASTs = try transpileGryphonRawASTs(fromASTDumpFiles: inputFiles)
		return try rawASTs.map { try generateGryphonAST(fromGryphonRawAST: $0) }
	}

	public static func transpileGryphonRawASTs(fromASTDumpFiles inputFiles: [String])
		throws -> [GryphonAST]
	{
		let asts = try inputFiles.map { try transpileSwiftAST(fromASTDumpFile: $0) }
		let translateAsMainFile = (inputFiles.count == 1)
		return try asts.map {
			try generateGryphonRawAST(fromSwiftAST: $0, asMainFile: translateAsMainFile)
		}
	}

	//
	internal static func handleWarning(
		file: String = #file,
		line: Int = #line,
		function: String = #function,
		message: String,
		details: String = "",
		sourceFile: SourceFile?,
		sourceFileRange: SourceFileRange?)
	{
		Compiler.warnings.append(
			Compiler.createErrorOrWarningMessage(
				file: file,
				line: line,
				function: function,
				message: message,
				details: details,
				sourceFile: sourceFile,
				sourceFileRange: sourceFileRange,
				isError: false))
	}

	public static func printErrorsAndWarnings() {
		if !errors.isEmpty {
			print("Errors:")
			for error in errors {
				print(error)
			}
		}

		if !warnings.isEmpty {
			print("Warnings:")
			for warning in warnings {
				print(warning)
			}
		}

		if hasErrorsOrWarnings() {
			print("Total: \(errors.count) errors and \(warnings.count) warnings.")
		}
	}

	public static func hasErrorsOrWarnings() -> Bool {
		return !errors.isEmpty || !warnings.isEmpty
	}

	public static func printErrorStatistics() {
		print("Errors: \(Compiler.errors.count). Warnings: \(Compiler.warnings.count).")

		let swiftASTDumpErrors = errors.compactMap { $0 as? SwiftTranslatorError }
		if !swiftASTDumpErrors.isEmpty {
			print("Swift AST translator failed to translate:")

			let swiftASTDumpHistogram = swiftASTDumpErrors.group { $0.astName }
			for (astName, errorArray) in
				swiftASTDumpHistogram.sorted(by: { $0.value.count > $1.value.count })
			{
				print("- \(errorArray.count) \(astName)s")
			}
		}

		let kotlinTranslatorErrors = errors.compactMap { $0 as? KotlinTranslatorError }
		if !kotlinTranslatorErrors.isEmpty {
			print("Kotlin translator failed to translate:")

			let kotlinTranslatorHistogram = kotlinTranslatorErrors.group { $0.astName }
			for (astName, errorArray) in
				kotlinTranslatorHistogram.sorted(by: { $0.value.count > $1.value.count })
			{
				print("- \(errorArray.count) \(astName)s")
			}
		}
	}

	static func createErrorOrWarningMessage(
		file: String = #file,
		line: Int = #line,
		function: String = #function,
		message: String,
		details: String,
		sourceFile: SourceFile?,
		sourceFileRange: SourceFileRange?,
		isError: Bool = true) -> String
	{
		let throwingFileName = file.split(separator: "/").last!.split(separator: ".").first!

		let errorOrWarning = isError ? "error" : "warning"

		if let sourceFile = sourceFile {
			let sourceFilePath = sourceFile.path
			let sourceFileURL = URL(fileURLWithPath: sourceFilePath)
			let relativePath = sourceFileURL.relativePath

			if let sourceFileRange = sourceFileRange {
				let sourceFileString = sourceFile.getLine(sourceFileRange.lineStart) ??
					"<<Unable to get line \(sourceFileRange.lineStart) in file \(relativePath)>>"

				var underlineString = ""
				if sourceFileRange.columnEnd < sourceFileString.count {
					for i in 1..<sourceFileRange.columnStart {
						let sourceFileCharacter = sourceFileString[
							sourceFileString.index(sourceFileString.startIndex, offsetBy: i - 1)]
						if sourceFileCharacter == "\t" {
							underlineString += "\t"
						}
						else {
							underlineString += " "
						}
					}
					underlineString += "^"
					if sourceFileRange.columnStart < sourceFileRange.columnEnd {
						for _ in (sourceFileRange.columnStart + 1)..<sourceFileRange.columnEnd {
							underlineString += "~"
						}
					}
				}

				return "\(relativePath):\(sourceFileRange.lineStart):" +
					"\(sourceFileRange.columnStart): \(errorOrWarning): \(message)\n" +
					"\(sourceFileString)\n" +
					"\(underlineString)\n" +
					"Thrown by \(throwingFileName):\(line) - \(function)\n" +
					details
			}
			else {
				return "\(relativePath): \(errorOrWarning): \(message)\n" +
					"Thrown by \(throwingFileName):\(line) - \(function)\n" +
					details
			}
		}
		else {
			return "\(errorOrWarning): \(message)\n" +
				"Thrown by \(throwingFileName):\(line) - \(function)\n" +
				details
		}
	}
}
