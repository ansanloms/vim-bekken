vim9script

class WinId
  public var prompt: number = -1
  public var result: number = -1
endclass

class Resource
  public var name: string = null_string
  public var filterKey: string = null_string
  public var list: list<dict<any>> = []
  public var results: list<dict<any>> = []
  public var selected: dict<any> = null_dict
endclass

export class Bekken
  var loading: bool = false
  var query: string = null_string
  var winid: WinId = WinId.new()
  var resource: Resource = Resource.new()

  var zindex: number = 100
  var size: dict<number> = { width: 160, height: 20 }
  var resultFileType: string = null_string

  def new(name: string, options: dict<any>): void
    this.resource.name = name

    this.query = options->has_key("query") ? options.query : ""
    this.zindex = options->has_key("zindex") ? options.zindex : 100
    this.size = options->has_key("size") ? options.size : { width: 160, height: 20 }
    this.resultFileType = options->has_key("resultFileType") ? options.resultFileType : null_string
  enddef

  def Open(args: list<any>): void
    this._SetPrompt()
    this._SetResult()

    this._Render()

    this.loading = true
    this._Loading()

    try
      call("bekken#resource#" .. this.resource.name .. "#ListAsync", [this._InitCb] + args)
    catch /E117.*/
      this._InitCb(call("bekken#resource#" .. this.resource.name .. "#List", args))
    endtry
  enddef

  def Close(): void
    if this.winid.prompt != -1
      this.winid.prompt->popup_close()
    endif

    if this.winid.result != -1
      this.winid.result->popup_close()
    endif
  enddef

  def Exists(): bool
    return this.winid.prompt != -1 && this.winid.result != -1
  enddef

  def GetResource(): Resource
    return this.resource->copy()
  enddef

  def GetWinId(): WinId
    return this.winid->copy()
  enddef

  def _InitCb(list: list<dict<any>>): bool
    this.resource.list = list

    try
      this.resource.filterKey = call("bekken#resource#" .. this.resource.name .. "#FilterKey", [])
    catch /E117.*/
      this.resource.filterKey = "line"
    endtry

    this._SetResults()
    this._SetSelected()

    this.loading = false
    this._Render()

    return true
  enddef

  def _SetPrompt(): void
    const promptPopupSize = this._GetPromptPopupSize()
    const promptPopupPosition = this._GetPromptPopupPosition()

    this.winid.prompt =  popup_create("", {
      title: "",
      line: promptPopupPosition.y,
      col: promptPopupPosition.x,
      minwidth: promptPopupSize.width,
      minheight: promptPopupSize.height,
      maxwidth: promptPopupSize.width,
      maxheight: promptPopupSize.height,
      firstline: 1,
      wrap: false,
      resize: false,
      zindex: this.zindex,
      close: "none",
      padding: [0, 1, 0, 1],
      border: [],
      borderchars: ["─", "│", "─", "│", "╭", "╮", "╯", "╰"],
      filter: (id: number, key: string) => this._FilterCb(id, key),
      filtermode: "a",
      mapping: false,
      callback: (id: number, result: number) => this._CloseCb(id, result),
    })

    win_execute(this.winid.prompt, "setlocal filetype=bekken-prompt")
  enddef

  def _SetResult(): void
    const resultPopupSize = this._GetResultPopupSize()
    const resultPopupPosition = this._GetResultPopupPosition()

    this.winid.result = popup_create("", {
      title: "",
      line: resultPopupPosition.y,
      col: resultPopupPosition.x,
      minwidth: resultPopupSize.width,
      minheight: 1,
      maxwidth: resultPopupSize.width,
      maxheight: resultPopupSize.height,
      firstline: 1,
      cursorline: true,
      hidden: true,
      wrap: false,
      resize: false,
      zindex: this.zindex + 1,
      close: "none",
      padding: [0, 1, 0, 1],
      border: [],
      borderchars: ["─", "│", "─", "│", "├", "┤", "╯", "╰"],
      scrollbar: false,
    })

    if (this.resultFileType != null)
      win_execute(this.winid.result, "setlocal filetype=" .. this.resultFileType)
    else
      win_execute(this.winid.result, "setlocal filetype=bekken-result")
    endif
  enddef

  def _GetPromptPopupSize(): dict<number>
    const maxWidth = &columns - 24

    return {
      width: maxWidth < this.size.width ? maxWidth : this.size.width,
      height: 1,
    }
  enddef

  def _GetResultPopupSize(): dict<number>
    const promptPopupSize = this._GetPromptPopupSize()
    const maxHeight = &lines - 8

    return {
      width: promptPopupSize.width,
      height: maxHeight < this.size.height ? maxHeight : this.size.height,
    }
  enddef

  def _GetPromptPopupPosition(): dict<number>
    const promptPopupSize = this._GetPromptPopupSize()
    const resultPopupSize = this._GetResultPopupSize()
    const totalHeight =  1 + promptPopupSize.height + 1 + resultPopupSize.height + 1

    return {
      x: float2nr(ceil(&columns / 2) - ceil(promptPopupSize.width / 2)),
      y: float2nr(ceil(&lines / 2) - ceil(totalHeight / 2)),
    }
  enddef

  def _GetResultPopupPosition(): dict<number>
    const promptPopupPosition = this._GetPromptPopupPosition()

    return {
      x: promptPopupPosition.x,
      y: promptPopupPosition.y + 2,
    }
  enddef

  def _FilterCb(id: number, key: string): bool
    if this.loading
      return true
    endif

    if this.winid.result == -1
      this._SetResult()
    endif

    if key == "\<Esc>"
      id->popup_close()
      return true
    endif

    if key == "\<Bs>" || (char2nr(key) >= 32 && char2nr(key) <= 126)
      this.query = key == "\<Bs>" ? strcharpart(this.query, 0, strchars(this.query) - 1) : (this.query .. key)
      this._SetResults()

      this._Render()
      this._SetSelected()
    endif

    if this.winid.result->popup_getpos().visible && ["\<Down>", "\<C-j>", "\<C-n>"]->indexof((i, v) => key == v) != -1
      win_execute(this.winid.result, "call cursor(" .. (line(".", this.winid.result) + 1) .. ", 0)", "silent")
      redraw
      this._SetSelected()
    endif

    if this.winid.result->popup_getpos().visible && ["\<Up>", "\<C-k>", "\<C-p>"]->indexof((i, v) => key == v) != -1
      win_execute(this.winid.result, "call cursor(" .. (line(".", this.winid.result) - 1) .. ", 0)", "silent")
      redraw
      this._SetSelected()
    endif

    return call("bekken#resource#" .. this.resource.name .. "#Filter", [key, this])
  enddef

  def _CloseCb(id: number, result: number): void
    if id != this.winid.prompt
      this.winid.prompt->popup_close()
    endif

    if id != this.winid.result
      this.winid.result->popup_close()
    endif

    this.query = ""

    this.winid.prompt = -1
    this.winid.result = -1

    this.resource.name = null_string
    this.resource.filterKey = null_string
    this.resource.list = []
    this.resource.results = []
    this.resource.selected = null_dict
  enddef

  def _Loading(): void
    if !this.loading
      return
    endif

    if !this.Exists()
      return
    endif

    this.winid.prompt->popup_show()
    this.winid.result->popup_show()

    const marks = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    const currentMark: string = this.winid.result->winbufnr()->getbufline(1)->join("")->trim()[0]
    const currentMarkIndex: number = marks->index(currentMark)
    const nextMarkIndex = (currentMarkIndex == -1 || currentMarkIndex >= (marks->len() - 1)) ? 0 : (currentMarkIndex + 1)

    popup_settext(this.winid.result, marks[nextMarkIndex] .. " Loading...")
    redraw

    timer_start(50, (_) => this._Loading())
  enddef

  def _SetResults(): void
    if this.query->len() > 0
      this.resource.results = matchfuzzy(
        this.resource.list,
        this.query,
        { key: this.resource.filterKey }
      )
    else
      this.resource.results = this.resource.list
    endif
  enddef

  def _SetSelected(): void
    if this.winid.result != -1 && this.resource.results->len() > (line(".", this.winid.result) - 1)
      this.resource.selected = this.resource.results[line(".", this.winid.result) - 1]
    else
      this.resource.selected = null_dict
    endif
  enddef

  def _Render(): void
    this._RenderPrompt()
    this._RenderResult()
    redraw
  enddef

  def _RenderPrompt(): void
    if this.winid.prompt == -1
      return
    endif

    var character = "➜"
    var count = this.resource.results->len() .. " / " .. this.resource.list->len()
    var queryMaxLength = popup_getpos(this.winid.prompt).width - (character->len() + count->len() + 7)

    popup_settext(this.winid.prompt, [
      character,
      this.query->strcharpart(this.query->len() - queryMaxLength, queryMaxLength)->printf("%-" .. queryMaxLength .. "S"),
      count,
    ]->join(" "))

    this.winid.prompt->popup_show()
  enddef

  def _RenderResult(): void
    if this.winid.result == -1
      return
    endif

    try
      popup_settext(
        this.winid.result,
        this.resource.results
          ->copy()
          ->map((line, target) => call(
            "bekken#resource#" .. this.resource.name .. "#Render",
            [line, target, this]
          ))
      )
    catch /E117.*/
      popup_settext(
        this.winid.result,
        this.resource.results
          ->copy()
          ->map((line, target) => target[this.resource.filterKey])
      )
    endtry

    if (this.resource.results->len() > 0)
      win_execute(this.winid.result, "call cursor(1, 0)", "silent")
      this.winid.result->popup_show()
    else
      this.winid.result->popup_hide()
    endif
  enddef

  def Resize(): void
    this._ResizePrompt()
    this._ResizeResult()
    redraw
  enddef

  def _ResizePrompt(): void
    if this.winid.prompt == -1
      return
    endif

    const promptPopupSize = this._GetPromptPopupSize()
    const promptPopupPosition = this._GetPromptPopupPosition()

    popup_move(this.winid.prompt, {
      line: promptPopupPosition.y,
      col: promptPopupPosition.x,
      minwidth: promptPopupSize.width,
      minheight: promptPopupSize.height,
      maxwidth: promptPopupSize.width,
      maxheight: promptPopupSize.height,
    })

    popup_setoptions(this.winid.prompt, {
      zindex: this.zindex,
    })

    this._RenderPrompt()
  enddef

  def _ResizeResult(): void
    if this.winid.result == -1
      return
    endif

    const resultPopupSize = this._GetResultPopupSize()
    const resultPopupPosition = this._GetResultPopupPosition()

    popup_move(this.winid.result, {
      line: resultPopupPosition.y,
      col: resultPopupPosition.x,
      minwidth: resultPopupSize.width,
      maxwidth: resultPopupSize.width,
      maxheight: resultPopupSize.height,
    })

    popup_setoptions(this.winid.result, {
      zindex: this.zindex + 1,
    })

    this._RenderResult()
  enddef
endclass


var bekkenList: dict<Bekken> = {}

export def Resize(): void
  for key in bekkenList->keys()
    if bekkenList[key].Exists()
      bekkenList[key].Resize()
    else
      bekkenList->remove(key)
    endif
  endfor
enddef

export def Open(name: string, args: list<any>, options: dict<any>): Bekken
  const key = rand()
  if bekkenList->has_key(key)
    return Open(name, args, options)
  endif

  bekkenList[key] = Bekken.new(name, options)
  bekkenList[key].Open(args)

  return bekkenList[key]
enddef
