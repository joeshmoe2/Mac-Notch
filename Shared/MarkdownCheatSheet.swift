import Foundation

/// The "Markdown Cheat Sheet" note created the first time either app runs.
@MainActor
enum MarkdownCheatSheet {
    static let fileName = "Markdown Cheat Sheet.md"
    private static let createdKey = "markdownCheatSheetCreated"

    /// Creates the cheat sheet once. Deleting it later won't bring it back;
    /// use "Restore Markdown Cheat Sheet" in settings for that.
    static func createIfNeeded(in store: NotesStore) {
        let defaults = NotesLocation.sharedDefaults
        guard !defaults.bool(forKey: createdKey) else { return }
        defaults.set(true, forKey: createdKey)
        restore(in: store)
    }

    @discardableResult
    static func restore(in store: NotesStore) -> Note {
        if let existing = store.note(fileName: fileName) { return existing }
        return store.createNote(body: text)
    }

    static let text = #"""
    # Markdown Cheat Sheet

    Type the **left** side in Edit mode; switch to **Preview** (or Split) to see the result on the right. Tick the boxes at the bottom — they really work.

    ## Basic syntax

    | Element | You type | You get |
    | --- | --- | --- |
    | Bold | `**bold text**` | **bold text** |
    | Italic | `*italicized text*` | *italicized text* |
    | Bold + italic | `***both***` | ***both*** |
    | Strikethrough | `~~The world is flat.~~` | ~~The world is flat.~~ |
    | Code | `` `code` `` | `code` |
    | Link | `[title](https://www.example.com)` | [title](https://www.example.com) |
    | Highlight | `==very important words==` | ==very important words== |
    | Subscript | `H~2~O` | H~2~O |
    | Superscript | `X^2^` | X^2^ |
    | Emoji | `:joy: :tada: :rocket:` | :joy: :tada: :rocket: |

    ## Headings

    ```
    # H1
    ## H2
    ### H3
    ```

    ### This is an H3

    ## Blockquote

    ```
    > Markdown is a lightweight markup language.
    ```

    > Markdown is a lightweight markup language.

    ## Lists

    ```
    1. First item
    2. Second item
    3. Third item

    - First item
    - Second item
      - Indented item
    ```

    1. First item
    2. Second item
    3. Third item

    - First item
    - Second item
      - Indented item

    ## Task list

    ```
    - [x] Write the press release
    - [ ] Update the website
    ```

    - [x] Write the press release
    - [ ] Update the website
    - [ ] Contact the media

    ## Code block

    Wrap code in three backticks, optionally with a language:

    ```json
    {
      "firstName": "John",
      "lastName": "Smith",
      "age": 25
    }
    ```

    ## Table

    ```
    | Syntax | Description |
    | ----------- | ----------- |
    | Header | Title |
    | Paragraph | Text |
    ```

    | Syntax | Description |
    | ----------- | ----------- |
    | Header | Title |
    | Paragraph | Text |

    Use `:---:` for centered or `---:` for right-aligned columns.

    ## Horizontal rule

    Three dashes on their own line: `---`

    ---

    ## Image

    `![alt text](image.jpg)` — use a web address, or a file name in your notes folder.

    ![NotchHub on GitHub](https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png)

    ## Footnote

    Here's a sentence with a footnote. [^1]

    [^1]: This is the footnote.

    ## Definition list

    ```
    term
    : definition
    ```

    Markdown
    : A plain-text way to write formatted documents.

    ## Heading IDs

    `### My Great Heading {#custom-id}` — the `{#…}` part is hidden in Preview.

    ## Keyboard shortcuts (NotchNotes)

    | Action | Shortcut |
    | --- | --- |
    | Bold | ⌘B |
    | Italic | ⌘I |
    | Strikethrough | ⇧⌘X |
    | Inline code | ⌘E |
    | Link | ⌘K |
    | Heading 1 / 2 / 3 | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
    | Bulleted / numbered list | ⇧⌘8 / ⇧⌘7 |
    | Checkbox | ⇧⌘L |
    | Quote | ⇧⌘' |
    | Highlight | ⇧⌘H |
    | Edit / Split / Preview | ⌘1 / ⌘2 / ⌘3 |
    """#
}
