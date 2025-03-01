vim9script

class WinId
  public var prompt: number = -1
  public var selection: number = -1
endclass

class Resource
  public var name: string = null_string
  public var filterKey: string = null_string
  public var list: list<dict<any>> = []
  public var selections: list<dict<any>> = []
  public var selected: dict<any> = null_dict
endclass

const marks = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
const upKeys = ["\<Down>", "\<C-j>", "\<C-n>"]
const downKeys = ["\<Up>", "\<C-k>", "\<C-p>"]

export class Bekken
  var loading: bool = false
  var query: string = ""
  var winid: WinId = WinId.new()
  var resource: Resource = Resource.new()

  var zindex: number = 100
  var size: dict<number> = { width: 560, height: 12 }
  var filetype: dict<string> = { prompt: "bekken-prompt", selection: "bekken-selection" }

  def new(resource: string, options: dict<any>): void
    this.resource.name = resource

    if options->has_key("query")
      this.query = options.query
    endif

    if options->has_key("zindex")
      this.zindex = options.zindex
    endif

    if options->has_key("size")
      this.size = options.size
    endif

    if options->has_key("filetype")
      this.filetype = options.filetype
    endif
  enddef

  def Run(args: list<any>): void
    this._SetPrompt()
    this._SetSelection()

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

    if this.winid.selection != -1
      this.winid.selection->popup_close()
    endif
  enddef

  def Exists(): bool
    return this.winid.prompt != -1 && this.winid.selection != -1
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

    this._SetSelections()
    this._SetSelected()

    this.loading = false
    this._Render()

    return true
  enddef

  def _SetPrompt(): void
    const promptPopupSize = this._GetPromptPopupSize()
    const promptPopupPosition = this._GetPromptPopupPosition()

    this.winid.prompt = popup_create("", {
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

    win_execute(this.winid.prompt, "setlocal filetype=" .. (this.filetype->has_key("prompt") ? this.filetype.prompt : "bekken-prompt"))
  enddef

  def _SetSelection(): void
    const selectionPopupSize = this._GetSelectionPopupSize()
    const selectionPopupPosition = this._GetSelectionPopupPosition()

    this.winid.selection = popup_create("", {
      title: "",
      line: selectionPopupPosition.y,
      col: selectionPopupPosition.x,
      minwidth: selectionPopupSize.width,
      minheight: 1,
      maxwidth: selectionPopupSize.width,
      maxheight: selectionPopupSize.height,
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

    win_execute(this.winid.selection, "setlocal filetype=" .. (this.filetype->has_key("selection") ? this.filetype.selection : "bekken-selection"))
  enddef

  def _GetPromptPopupSize(): dict<number>
    const maxWidth = &columns - 24

    return {
      width: maxWidth < this.size.width ? maxWidth : this.size.width,
      height: 1,
    }
  enddef

  def _GetSelectionPopupSize(): dict<number>
    const promptPopupSize = this._GetPromptPopupSize()
    const maxHeight = &lines - 20

    return {
      width: promptPopupSize.width,
      height: maxHeight < this.size.height ? maxHeight : this.size.height,
    }
  enddef

  def _GetPromptPopupPosition(): dict<number>
    const promptPopupSize = this._GetPromptPopupSize()
    const selectionPopupSize = this._GetSelectionPopupSize()
    const totalHeight = 1 + promptPopupSize.height + 1 + selectionPopupSize.height + 1

    return {
      x: float2nr(ceil(&columns / 2) - ceil(promptPopupSize.width / 2)),
      y: float2nr(ceil(&lines / 2) - ceil(totalHeight / 2)),
    }
  enddef

  def _GetSelectionPopupPosition(): dict<number>
    const promptPopupPosition = this._GetPromptPopupPosition()

    return {
      x: promptPopupPosition.x,
      y: promptPopupPosition.y + 2,
    }
  enddef

  def _WithLazyRedraw(Callback: func)
    const old_lazyredraw = &lazyredraw
    set lazyredraw
    try
      Callback()
    finally
      redraw
      &lazyredraw = old_lazyredraw
    endtry
  enddef

  def _FilterCb(id: number, key: string): bool
    if this.loading
      return true
    endif

    if this.winid.selection == -1
      this._SetSelection()
    endif

    if key == "\<Esc>"
      id->popup_close()
      return true
    endif

    if upKeys->index(key) >= 0
      this.loading = true
      timer_start(1, (timer) => {
        this._WithLazyRedraw(() => {
          win_execute(this.winid.selection, $"noautocmd call setpos('.', [{winbufnr(this.winid.selection)}, {line('.', this.winid.selection) + 1}, 0, 0])", 'silent')
          this._SetSelected()
        })
        this.loading = false
      })
      return true
    endif

    if downKeys->index(key) >= 0
      this.loading = true
      timer_start(1, (timer) => {
        this._WithLazyRedraw(() => {
          win_execute(this.winid.selection, $"noautocmd call setpos('.', [{winbufnr(this.winid.selection)}, {line('.', this.winid.selection) - 1}, 0, 0])", 'silent')
          this._SetSelected()
        })
        this.loading = false
      })
      return true
    endif

    if key == "\<Bs>" || (char2nr(key) >= 32 && char2nr(key) <= 126)
      this.query = key == "\<Bs>" ? strcharpart(this.query, 0, strchars(this.query) - 1) : (this.query .. key)
      this._SetSelections()
      this._SetSelected()
      this._Render()
    endif

    return call("bekken#resource#" .. this.resource.name .. "#Filter", [key, this])
  enddef

  def _CloseCb(id: number, result: number): void
    if id != this.winid.prompt
      this.winid.prompt->popup_close()
    endif

    if id != this.winid.selection
      this.winid.selection->popup_close()
    endif

    this.query = ""

    this.winid.prompt = -1
    this.winid.selection = -1

    this.resource.name = null_string
    this.resource.filterKey = null_string
    this.resource.list = []
    this.resource.selections = []
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
    this.winid.selection->popup_show()

    const currentMark: string = this.winid.selection->winbufnr()->getbufline(1)->join("")->trim()[0]
    const currentMarkIndex: number = marks->index(currentMark)
    const nextMarkIndex = (currentMarkIndex == -1 || currentMarkIndex >= (marks->len() - 1)) ? 0 : (currentMarkIndex + 1)

    this._WithLazyRedraw(() => {
      popup_settext(this.winid.selection, marks[nextMarkIndex] .. " Loading...")
    })

    timer_start(50, (_) => this._Loading())
  enddef

  def _SetSelections(): void
    if this.query->len() > 0
      this.resource.selections = this.resource.list->matchfuzzy(
        this.query,
        { key: this.resource.filterKey }
      )
    else
      this.resource.selections = this.resource.list
    endif
  enddef

  def _SetSelected(): void
    if this.winid.selection != -1 && this.resource.selections->len() > (line(".", this.winid.selection) - 1)
      this.resource.selected = this.resource.selections[line(".", this.winid.selection) - 1]
    else
      this.resource.selected = null_dict
    endif
  enddef

  def _Render(): void
    this._WithLazyRedraw(() => {
      this._RenderPrompt()
      this._RenderSelection()
    })
  enddef

  def _RenderPrompt(): void
    if this.winid.prompt == -1
      return
    endif

    var character = "➜"
    var count = this.resource.selections->len() .. " / " .. this.resource.list->len()
    var queryMaxLength = popup_getpos(this.winid.prompt).width - (character->len() + count->len() + 7)

    popup_settext(this.winid.prompt, [
      character,
      this.query->strcharpart(this.query->len() - queryMaxLength, queryMaxLength)->printf("%-" .. queryMaxLength .. "S"),
      count,
    ]->join(" "))

    this.winid.prompt->popup_show()
  enddef

  def _RenderSelection(): void
    if this.winid.selection == -1
      return
    endif

    try
      popup_settext(
        this.winid.selection,
        this.resource.selections
          ->copy()
          ->map((line, target) => call(
            "bekken#resource#" .. this.resource.name .. "#Render",
            [line, target, this]
          ))
      )
    catch /E117.*/
      popup_settext(
        this.winid.selection,
        this.resource.selections
          ->copy()
          ->map((line, target) => target[this.resource.filterKey])
      )
    endtry

    if (this.resource.selections->len() > 0)
      win_execute(this.winid.selection, "call cursor(1, 0)", "silent")
      this.winid.selection->popup_show()
    else
      this.winid.selection->popup_hide()
    endif
  enddef

  def Resize(): void
    this._WithLazyRedraw(() => {
      this._ResizePrompt()
      this._ResizeSelection()
    })
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

  def _ResizeSelection(): void
    if this.winid.selection == -1
      return
    endif

    const selectionPopupSize = this._GetSelectionPopupSize()
    const selectionPopupPosition = this._GetSelectionPopupPosition()

    popup_move(this.winid.selection, {
      line: selectionPopupPosition.y,
      col: selectionPopupPosition.x,
      minwidth: selectionPopupSize.width,
      maxwidth: selectionPopupSize.width,
      maxheight: selectionPopupSize.height,
    })

    popup_setoptions(this.winid.selection, {
      zindex: this.zindex + 1,
    })

    this._RenderSelection()
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

export def Run(resource: string, args: list<any>, options: dict<any>): Bekken
  const key = rand()
  if bekkenList->has_key(key)
    return Run(resource, args, options)
  endif

  bekkenList[key] = Bekken.new(resource, options)
  bekkenList[key].Run(args)

  return bekkenList[key]
enddef
