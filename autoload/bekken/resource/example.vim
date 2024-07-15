vim9script

import autoload "bekken.vim" as b

export def FilterKey(): string
  return "val"
enddef

#export def ListAsync(Cb: func(list<dict<any>>): bool, ...args: list<any>): void
#  var result: list<dict<any>> = []
#
#  job_start(["git", "--help"], {
#    out_cb: (channel: channel, msg: string) => result->add({val: msg}),
#    exit_cb: (job: job, status: number) => Cb(result),
#  })
#enddef

export def List(...args: list<any>): list<dict<any>>
  const chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

  sleep 5

  return range(1, 10000)->map((key1, val1) => ({
    val: range(1, 100)->map((key2, val2) => chars[rand() % chars->len()])->join(""),
  }))
enddef

export def Render(line: number, target: dict<any>, bekken: b.Bekken): string
  return target.val
enddef

export def Filter(key: string, bekken: b.Bekken): bool
  const selected = bekken.GetResource().selected

  if "\<Cr>" == key
    if selected != null
      echo selected.val
    endif

    bekken.Close()
  endif

  return true
enddef
