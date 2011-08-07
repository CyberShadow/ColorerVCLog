

import std.stdio;
import std.string;
import std.process;
import std.file;
import std.path;
import std.conv;
import std.exception;
import std.xml;

alias std.string.join join;

enum OUTDIR = "html" ~ sep;
enum STYLE = 
	`div { margin: 1px 50px 1px 100px; border: 1px solid #888; padding: 2px; white-space: pre-wrap; }` ~
	`.Warning { background-color: #FFFF88 }` ~
	`.CodeAnalysis { background-color: #FFAAFF }`;

void main(string[] args)
{
	if (args.length != 2)
		throw new Exception(format("Usage: %s BUILDLOG", args[0]));

	struct Annotation
	{
		enum Type { Warning, CodeAnalysis }
		Type type;
		string message;
	}
	
	Annotation[] annotations[string /*file*/][int /*line*/];
	Annotation* lastAnnotation;

	string rootDir;
	auto annotationType = Annotation.Type.Warning;

	foreach (line; File(args[1]).byLine)
	{
		if (line.startsWith(`     1>Project "`))
			rootDir = toLower(dirname(line.split(`"`)[1]).idup) ~ sep;
		else
		if (line.startsWith(`     1>`) && line.indexOf(`): `)>0)
		{
			line = line[7..$];
			auto fileName = line[0..line.indexOf(`(`)].idup;
			auto lineNumber = to!int(line[line.indexOf(`(`)+1..line.indexOf(`): `)]);
			auto message = strip(line[line.indexOf(`): `)+3..$].idup);
			if (toLower(fileName).startsWith(rootDir))
				fileName = fileName[rootDir.length..$];
			annotations[fileName][lineNumber] ~= Annotation(annotationType, message);
			lastAnnotation = &annotations[fileName][lineNumber][$-1];
		}
		else
		if (line.startsWith(`                 `))
			lastAnnotation.message ~= "\n" ~ line[17..$];
		else
		if (line.startsWith(`         Running Code Analysis for C/C++...`))
			annotationType = Annotation.Type.CodeAnalysis;
	}

	string[] reportFiles;

	foreach (file, lines; annotations)
	{
		if (isabs(file))
			continue;
		reportFiles ~= file;
		stderr.writeln(file);
		auto dir = dirname(OUTDIR ~ file);
		if (!exists(dir))
			mkdirRecurse(dir);
		auto htmlFile = OUTDIR ~ file ~ ".html";
		if (exists(htmlFile))
			continue;

		auto tmpFile = htmlFile ~ ".tmp";
		scope(exit) remove(tmpFile);
		enforce(system(format(`colorer -ln -dc -h "%s" -o"%s"`, rootDir ~ file, tmpFile))==0);

		auto output = File(htmlFile, "wb");
		auto tmp = File(tmpFile); scope(exit) tmp.close();
		foreach (line; tmp.byLine)
		{
			if (line.startsWith(`<html>`))
				line = line[0..6] ~ `<head><style>` ~ STYLE ~ `</style></head>` ~ line[6..$];

			if (line.startsWith(`<`))
			{
				output.writeln(line);
				continue;
			}

			auto p = line.indexOf(`:`);
			assert(p > 0);
			auto lineNumber = to!int(strip(line[0..p]))+1;
			line = rightJustify(to!string(lineNumber), p) ~ line[p..$]; // fix line number to be 1-based
			output.writeln(line);

			if (lineNumber in lines)
				foreach (annotation; lines[lineNumber])
					output.write(`<div class="`~to!string(annotation.type)~`">` ~ encode(annotation.message) ~ `</div>`);
		}
	}

	{
		import std.algorithm, std.array;
		std.file.write(OUTDIR ~ "index.html", `<html><body><ul>` ~ array(map!q{`<li><a href="`~a~`.html">`~a~`</a></li>`}(reportFiles.sort)).join() ~ `</ul></li></ul></body></html>`);
	}
}
