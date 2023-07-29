#!/bin/env -S nim --opt:speed -d:danger r generate.nim
import std/[
  json,
  tables,
  parsecsv
]
from std/os import `/`, createDir, setCurrentDir
from std/strformat import fmt
from std/streams import newFileStream
from std/strutils import split, `%`

from pkg/bibleTools import `$`, parseBibleVerses, inOzzuuBible, ALPortuguese,
                            BibleVerse, BibleBook, en, enAbbr

include "template/crossrefs.md.nimf"
include "template/crossrefsBookList.md.nimf"
include "template/crossrefsChapterList.md.nimf"

let
  dataTsv = "data/crossrefs.tsv"
  outJson = "json/crossrefs.json"
  outMarkdownDir = "md"

var
  crossrefs: OrderedTable[string, seq[string]]

func parseVerse(text: string): string =
  ## Transform to a understandable verse text
  var
    bookName = true
    chapter = false
    getBookNameAndChapter = true
  let verses = text.split "-"
  for i, verse in verses:
    for ch in verse:
      if ch == '.':
        if getBookNameAndChapter:
          if bookName:
            result.add ' '
            chapter = true
          elif chapter:
            getBookNameAndChapter = false
            result.add ':'
            chapter = false
            bookName = false
        else:
          if bookName:
            result.add '-'
            chapter = true
          elif chapter:
            chapter = false
            bookName = false
        bookName = false
      else:
        if not getBookNameAndChapter and (bookName or chapter):
          continue
        result.add ch
    if i < verses.len - 1:
      bookName = true
      chapter = false

proc add(self: var type crossrefs; verse, crossref: string) =
  ## Add new cross reference verse to the given verse list
  let
    verse = verse.parseVerse
    crossref = crossref.parseVerse
  if self.hasKey verse:
    self[verse].add crossref
  else:
    self[verse] = @[crossref]

when isMainModule:
  var s = dataTsv.newFileStream fmRead
  if s == nil:
    quit "Cannot open the file: " & dataTsv

  var csvParser: CsvParser
  csvParser.open(s, dataTsv, '\t')
  readHeaderRow csvParser
  while csvParser.readRow:
    let row = csvParser.row
    crossrefs.add(row[0], row[1])
  close csvParser

  # Write JSON data file
  outJson.writeFile($ %*crossrefs)

  # Create markdown
  proc verseMdLink(verse: BibleVerse): string =
    ## returns `[Verse text](Ozzuu Bible link)`
    let
      url = verse.inOzzuuBible "pt_yah"
      text = verse.`$`(hebrewTransliteration = true, shortBook = false, forceLang = ALPortuguese)
    result = fmt"[{text}]({url})"
  proc verseHtmlLink(verse: BibleVerse): string =
    ## returns `<h2 id="verseNum"><a href="Ozzuu Bible link" target="_blank">Verse text</a></h2>`
    let
      url = verse.inOzzuuBible "pt_yah"
      text = verse.`$`(hebrewTransliteration = true, shortBook = false, forceLang = ALPortuguese)
    result = fmt"""<h2 id="{verse.verses[0]}"><a href="{url}" target="_blank">{text}</a></h2>"""
    
  var mdData: OrderedTable[BibleBook, OrderedTable[int, string]] # Table[bookName, Table[chapter, data]]

  proc add(mdData: var type mdData; verse: BibleVerse; md: string) =
    let
      book = verse.book.book
      chapter = verse.chapter
    if mdData.hasKey book:
      if mdData[book].hasKey chapter:
        mdData[book][chapter].add md
      else:
        mdData[book][chapter] = md
    else:
      mdData[book] = {
        chapter: md
      }.toOrderedTable
    mdData[book][chapter].add "\l"


  for (verse, crossRefs) in crossrefs.pairs:
    let
      verse = verse.parseBibleVerses[0].parsed
    mdData.add(verse, verse.verseHtmlLink & "\l")
    for crossRef in crossRefs:
      let refVerse = crossRef.parseBibleVerses[0].parsed
      mdData.add(verse, fmt"- {refVerse.verseMdLink}")

  createDir outMarkdownDir
  var bookListMd = ""
  setCurrentDir outMarkdownDir
  for (book, chapters) in mdData.pairs:
    var chapterListMd = ""
    let dir = book.enAbbr
    bookListMd.add fmt"## [{book.en}]({outMarkdownDir / dir}#readme)"
    bookListMd.add "\l"
    createDir dir
    setCurrentDir dir
    for (chapter, md) in chapters.pairs:
      chapterListMd.add fmt"## [Chapter {chapter}]({chapter}.md)"
      chapterListMd.add "\l"
      fmt"{chapter}.md".writeFile crossrefsMd(
        bookName = book.en,
        crossrefs = md,
        bookCode = ord book,
        chapter = chapter
      )
    "readme.md".writeFile book.en.crossrefsChapterListMd(chapterListMd, ord book)
    setCurrentDir ".."
  setCurrentDir ".."
  "readme.md".writeFile crossrefsBookListMd bookListMd
