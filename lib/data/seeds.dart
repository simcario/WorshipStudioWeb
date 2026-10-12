import '../models.dart';

/// Public-domain demo songs added to a fresh library.
List<Song> seedSongs() => [
      Song(
        title: 'Amazing Grace',
        artist: 'John Newton',
        key: 'G',
        tempo: 80,
        timeSig: '3/4',
        tags: ['Demo', 'Hymn'],
        copyright: 'Public Domain',
        content: '''{title: Amazing Grace}
{artist: John Newton}
{key: G}
{tempo: 80}
{time: 3/4}

{start_of_verse: Verse 1}
A[G]mazing grace, how [C]sweet the [G]sound
That saved a wretch like [D]me
I [G]once was lost, but [C]now am [G]found
Was [Em]blind, but [D]now I [G]see
{end_of_verse}

{start_of_verse: Verse 2}
'Twas [G]grace that taught my [C]heart to [G]fear
And grace my fears re[D]lieved
How [G]precious did that [C]grace ap[G]pear
The [Em]hour I [D]first be[G]lieved
{end_of_verse}

{start_of_verse: Verse 3}
When [G]we've been there ten [C]thousand [G]years
Bright shining as the [D]sun
We've [G]no less days to [C]sing God's [G]praise
Than [Em]when we'd [D]first be[G]gun
{end_of_verse}
''',
      ),
      Song(
        title: 'Holy, Holy, Holy',
        artist: 'Reginald Heber / John B. Dykes',
        key: 'D',
        tempo: 92,
        timeSig: '4/4',
        tags: ['Demo', 'Hymn'],
        copyright: 'Public Domain',
        content: '''{title: Holy, Holy, Holy}
{artist: Reginald Heber / John B. Dykes}
{key: D}
{tempo: 92}
{time: 4/4}

Verse 1:
[D]Holy, holy, [Bm]ho[A]ly, [D]Lord [G]God Al[D]mighty
[A]Early in the [D]morning our [E]song shall rise to [A]Thee
[D]Holy, holy, [Bm]ho[A]ly, [D]merci[G]ful and [D]mighty
[Bm]God in three [D]Persons, [G]blessed [A]Trini[D]ty

Verse 2:
[D]Holy, holy, [Bm]ho[A]ly, [D]all the [G]saints a[D]dore Thee
[A]Casting down their [D]golden crowns a[E]round the glassy [A]sea
[D]Cherubim and [Bm]sera[A]phim [D]falling [G]down be[D]fore Thee
[Bm]Who wert and [D]art and [G]ever[A]more shalt [D]be
''',
      ),
    ];
