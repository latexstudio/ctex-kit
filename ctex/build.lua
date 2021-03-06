#!/usr/bin/env texlua

module = "ctex"

packtdszip = true

sourcefiles = {"ctex.dtx", "ctexpunct.spa"}
unpackfiles = {"ctex.dtx"}
installfiles = {"*.sty", "*.cls", "*.def", "*.cfg", "*.fd", "zh*.tex", "ctex*spa*.tex"}
cleanfiles = {"ctex.ver", "*.pdf", "*.zip", "*.log"}
unpackexe = "xetex"
typesetexe = "xelatex"

gbkfiles = {"ctex-name-gbk.cfg"}
generic_insatllfiles = {"zh*.tex", "ctex*spa*.tex"}
subtexdirs = {
    ["config"] = "*.cfg",
    ["fd"] = "*.fd",
    ["engine"] = "ctex-engine-*.def",
    ["fontset"] = "ctex-fontset-*.def",
    ["scheme"] = "ctex-scheme-*.def",
}
makeindexexe = "zhmakeindex"

dtxchecksum = dofile("../tool/dtxchecksum.lua").checksum

function append_newline(file)
  if os_windows then
    os.execute("echo.>> " .. file)
  else
    os.execute("echo >> " .. file)
  end
end

function shellescape(s)
  if not os_windows then
    s = s:gsub([[\]], [[\\]])
    s = s:gsub([[%$]], [[\$]])
  end
  return s
end

function extract_git_version()
  os.execute(shellescape([[git log -1 --pretty=format:"\def\ctexPutVersion{\string\GetIdInfo]] ..
  	[[$Id: ctex.dtx %h %ai %an <%ae> $}" ctex.dtx > ctex.ver]]))
  append_newline("ctex.ver")
  os.execute(shellescape([[git log -1 --pretty=format:"\def\ctexGetVersionInfo{\GetIdInfo]] ..
  	[[$Id: ctex.dtx %h %ai %an <%ae> $}" ctex.dtx >> ctex.ver]]))
end

function mv(src, dest)
  local mv = "mv"
  if os_windows then
    mv = "move /y"
    src = unix_to_win(src)
    dest = unix_to_win(dest)
  end
  os.execute(mv .. " " .. src .. " " .. dest .. " > " .. os_null)
end

function hooked_bundleunpack()
  extract_git_version()
  -- Unbundle
  unhooked_bundleunpack()
  -- UTF-8 to GBK conversion
  for _,f in ipairs(gbkfiles) do
    local f_utf = unpackdir .. "/" .. f
    local f_gbk = unpackdir .. "/" .. f .. ".gbk"
    if os_windows then
      f_utf = unix_to_win(f_utf)
      f_gbk = unix_to_win(f_gbk)
    end
    os.execute("iconv -f utf-8 -t gbk " .. f_utf .. " > " .. f_gbk)
    mv(f_gbk, f_utf)
  end
end

-- 修改自 l3build.lua 2015/04/02 r5564 的 doc() 函数
-- 只修改了 makeindex 的命令为可配置的
function mod_doc ()
  local function typeset (file)
    local name = stripext (file)
    -- A couple of short functions to deal with the repeated steps in a
    -- clear way
    local function biber (name)
      if fileexists (typesetdir .. "/" .. name .. ".bcf") then
        return (run (typesetdir, "biber " .. name))
      end
    end
    local function makeindex (name, inext, outext, logext, style)
      if fileexists (typesetdir .. "/" .. name .. inext) then
        return (
          run (
            typesetdir ,
            makeindexexe .. " -s " .. style .. " -o " .. name .. outext
              .. " -t " .. name .. logext .. " "  .. name .. inext
            )
          )
      end
    end
    local function typeset (file)
      return (
        os.execute (
            os_setenv .. " TEXINPUTS=" .. typesetdir ..
              os_pathsep .. localdir .. (typesetsearch and os_pathsep or "") ..
              os_concat ..
            typesetexe .. " " .. typesetopts ..
              " -output-directory=" .. typesetdir ..
              " \"" .. typesetcmds ..
              "\\input " .. typesetdir .. "/" .. file .. "\""
          )
      )
    end
    auxclean ()
    os.remove (name .. ".pdf")
    print ("Typesetting " .. name)
    local errorlevel = typeset (file)
    if errorlevel ~= 0 then
      print (" ! Compilation failed")
      return (errorlevel)
    else
      biber (name)
      makeindex (name, ".glo", ".gls", ".glg", glossarystyle)
      makeindex (name, ".idx", ".ind", ".ilg", indexstyle)
      typeset (file)
      typeset (file)
      cp (name .. ".pdf", typesetdir, ".")
    end
    return (errorlevel)
  end
  -- Set up
  cleandir (typesetdir)
  for _,i in ipairs (sourcefiles) do
    cp (i, ".", typesetdir)
  end
  for _,i in ipairs (typesetfiles) do
    cp (i, ".", typesetdir)
  end
  for _,i in ipairs (typesetsuppfiles) do
    cp (i, supportdir, typesetdir)
  end
  depinstall (typesetdeps)
  unpack ()
  -- Main loop for doc creation
  for _,i in ipairs (typesetfiles) do
    for _,j in ipairs (filelist (".", i)) do
      local errorlevel = typeset (j)
      if errorlevel ~= 0 then
        return (errorlevel)
      end
    end
  end
  return 0
end

function hooked_copytds()
  unhooked_copytds()
  -- 移动文件到 tex/generic/<module>/ 目录
  local tds_latexdir = tdsdir .. "/tex/latex/" .. module
  local tds_genericdir = tdsdir .. "/tex/generic/" .. module
  mkdir(tds_genericdir)
  for _,glob in ipairs(generic_insatllfiles) do
    for _,f in ipairs(filelist(tds_latexdir, glob)) do
      mv(tds_latexdir .. "/" .. f, tds_genericdir .. "/" .. f)
    end
  end
  -- 移动文件到 tex/latex/<module>/ 下的子目录
  for subdir,glob in pairs(subtexdirs) do
    mkdir(tds_latexdir .. "/" .. subdir)
    for _,f in ipairs(filelist(tds_latexdir, glob)) do
      mv(tds_latexdir .. "/" .. f, tds_latexdir .. "/" .. subdir .. "/" .. f)
    end
  end
end

function hooked_bundlectan()
  local err = unhooked_bundlectan()
  -- 复制 docstrip 生成的 README 文件
  if err == 0 then
    for _,f in ipairs (readmefiles) do
      cp(f, unpackdir, ctandir .. "/" .. ctanpkg .. "/" .. stripext(f))
      cp(f, unpackdir, tdsdir .. "/doc/" .. tdsroot .. "/" .. bundle .. "/" .. stripext(f))
    end
  end
  return err
end

-- 只对 .dtx 进行 \CheckSum 校正
function checksum()
  unpack ()
  -- 不进行重复解包
  unpack = function() end
  for _,glob in ipairs(typesetfiles) do
    for _,f in ipairs(filelist(".", glob)) do
      if f:sub(-4) == ".dtx" then
        dtxchecksum(f, localdir)
      end
    end
  end
end

function hooked_help()
  unhooked_help()
  print " build checksum              - adjust checksum"
end

function main (target, file, engine)
  unhooked_bundleunpack = bundleunpack
  bundleunpack = hooked_bundleunpack
  doc = function()
    checksum()
    return mod_doc()
  end
  unhooked_copytds = copytds
  copytds = hooked_copytds
  unhooked_bundlectan = bundlectan
  bundlectan = hooked_bundlectan
  unhooked_help = help
  help = hooked_help
  if target == "checksum" then
    checksum()
  else
    stdmain(target, file, engine)
  end
end

kpse.set_program_name("kpsewhich")
dofile(kpse.lookup("l3build.lua"))

-- vim:sw=2:et
