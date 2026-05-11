BeforeAll {
    . "$PSScriptRoot\Scoop-TestLib.ps1"
    . "$PSScriptRoot\..\lib\core.ps1"
    . "$PSScriptRoot\..\lib\system.ps1"
    . "$PSScriptRoot\..\lib\manifest.ps1"
    . "$PSScriptRoot\..\lib\install.ps1"
}

Describe 'appname_from_url' -Tag 'Scoop' {
    It 'should extract the correct name' {
        appname_from_url 'https://example.org/directory/foobar.json' | Should -Be 'foobar'
    }
}

Describe 'is_in_dir' -Tag 'Scoop', 'Windows' {
    It 'should work correctly' {
        is_in_dir 'C:\test' 'C:\foo' | Should -BeFalse
        is_in_dir 'C:\test' 'C:\test\foo\baz.zip' | Should -BeTrue
        is_in_dir "$PSScriptRoot\..\" "$PSScriptRoot" | Should -BeFalse
    }
}

Describe 'env add and remove path' -Tag 'Scoop', 'Windows' {
    BeforeAll {
        # test data
        $manifest = @{
            'env_add_path' = @('foo', 'bar', '.', '..')
        }
        $testdir = Join-Path $PSScriptRoot 'path-test-directory'
        $global = $false
    }

    It 'should concat the correct path' {
        Mock Add-Path {}
        Mock Remove-Path {}

        # adding
        env_add_path $manifest $testdir $global
        Should -Invoke -CommandName Add-Path -Times 1 -ParameterFilter { $Path -like "$testdir\foo" }
        Should -Invoke -CommandName Add-Path -Times 1 -ParameterFilter { $Path -like "$testdir\bar" }
        Should -Invoke -CommandName Add-Path -Times 1 -ParameterFilter { $Path -like $testdir }
        Should -Invoke -CommandName Add-Path -Times 0 -ParameterFilter { $Path -like $PSScriptRoot }

        env_rm_path $manifest $testdir $global
        Should -Invoke -CommandName Remove-Path -Times 1 -ParameterFilter { $Path -like "$testdir\foo" }
        Should -Invoke -CommandName Remove-Path -Times 1 -ParameterFilter { $Path -like "$testdir\bar" }
        Should -Invoke -CommandName Remove-Path -Times 1 -ParameterFilter { $Path -like $testdir }
        Should -Invoke -CommandName Remove-Path -Times 0 -ParameterFilter { $Path -like $PSScriptRoot }
    }
}

Describe 'shim_def' -Tag 'Scoop' {
    It 'should use strings correctly' {
        $target, $name, $shimArgs = shim_def 'command.exe'
        $target | Should -Be 'command.exe'
        $name | Should -Be 'command'
        $shimArgs | Should -BeNullOrEmpty
    }

    It 'should expand the array correctly' {
        $target, $name, $shimArgs = shim_def @('foo.exe', 'bar')
        $target | Should -Be 'foo.exe'
        $name | Should -Be 'bar'
        $shimArgs | Should -BeNullOrEmpty

        $target, $name, $shimArgs = shim_def @('foo.exe', 'bar', '--test')
        $target | Should -Be 'foo.exe'
        $name | Should -Be 'bar'
        $shimArgs | Should -Be '--test'
    }
}

Describe 'unlink_current' -Tag 'Scoop', 'Windows' {
    It 'can unlink a normal current junction while reverse junction is configured' {
        Mock get_config {
            if ($name -eq 'REVERSE_JUNCTION') { return $true }
            return $false
        }

        $appdir = Join-Path $TestDrive 'apps\testapp'
        $versiondir = Join-Path $appdir '1.0.0'
        $currentdir = Join-Path $appdir 'current'
        ensure $versiondir | Out-Null
        New-DirectoryJunction $currentdir $versiondir | Out-Null

        unlink_current $versiondir 'normal' | Should -Be $currentdir

        Test-Path $currentdir | Should -BeFalse
        Test-Path $versiondir | Should -BeTrue
    }
}

Describe 'link_current' -Tag 'Scoop', 'Windows' {
    It 'creates a version junction to current in reverse mode' {
        Mock get_config {
            if ($name -eq 'REVERSE_JUNCTION') { return $true }
            return $false
        }

        $appdir = Join-Path $TestDrive 'apps\testapp'
        $versiondir = Join-Path $appdir '1.0.0'
        $currentdir = Join-Path $appdir 'current'
        ensure $currentdir | Out-Null

        link_current $versiondir | Should -Be $currentdir

        (Get-Item $versiondir).Target | Should -Be $currentdir
        Test-Path $currentdir | Should -BeTrue

        attrib $versiondir -R /L
    }

    It 'does not treat an unset no_junction as enabled' {
        Mock get_config {
            if ($name -eq 'REVERSE_JUNCTION') { return $true }
            return $default
        }

        $appdir = Join-Path $TestDrive 'apps\unset-no-junction'
        $versiondir = Join-Path $appdir '1.0.0'
        $currentdir = Join-Path $appdir 'current'
        ensure $currentdir | Out-Null

        link_current $versiondir | Should -Be $currentdir

        (Get-Item $versiondir).Target | Should -Be $currentdir

        attrib $versiondir -R /L
    }
}

Describe 'reverse layout metadata' -Tag 'Scoop', 'Windows' {
    BeforeEach {
        $script:old_scoopdir = $scoopdir
        $scoopdir = $TestDrive
    }

    AfterEach {
        $scoopdir = $script:old_scoopdir
    }

    It 'falls back to current when version directory is missing' {
        $app = 'testapp'
        $appdir = Join-Path $TestDrive "apps\$app"
        $currentdir = Join-Path $appdir 'current'
        ensure $currentdir | Out-Null

        [IO.File]::WriteAllText((Join-Path $currentdir 'manifest.json'), '{ "version": "1.2.3" }')
        [IO.File]::WriteAllText((Join-Path $currentdir 'install.json'), '{ "architecture": "64bit" }')

        (installed_manifest $app '1.2.3' $false).version | Should -Be '1.2.3'
        (install_info $app '1.2.3' $false).architecture | Should -Be '64bit'
        get_junction_mode $app $false | Should -Be 'reverse'
    }
}

Describe 'persist_def' -Tag 'Scoop' {
    It 'parses string correctly' {
        $source, $target = persist_def 'test'
        $source | Should -Be 'test'
        $target | Should -Be 'test'
    }

    It 'should handle sub-folder' {
        $source, $target = persist_def 'foo/bar'
        $source | Should -Be 'foo/bar'
        $target | Should -Be 'foo/bar'
    }

    It 'should handle arrays' {
        # both specified
        $source, $target = persist_def @('foo', 'bar')
        $source | Should -Be 'foo'
        $target | Should -Be 'bar'

        # only first specified
        $source, $target = persist_def @('foo')
        $source | Should -Be 'foo'
        $target | Should -Be 'foo'

        # null value specified
        $source, $target = persist_def @('foo', $null)
        $source | Should -Be 'foo'
        $target | Should -Be 'foo'
    }
}
