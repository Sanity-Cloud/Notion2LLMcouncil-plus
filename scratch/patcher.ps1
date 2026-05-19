$File = "X:\Code\Notion2LLMcouncil-plus\vendor\llm-council-plus\frontend\src\App.jsx"
$Content = Get-Content $File -Raw

$Content = $Content -replace '      setConversations\(\(prev\) =>\s*convs\.map\(\(conv\) => \{\s*const local = prev\.find\(\(item\) => item\.id === conv\.id\);\s*if \(\s*local &&\s*isDefaultConversationTitle\(conv\.title\) &&\s*!isDefaultConversationTitle\(local\.title\)\s*\) \{\s*return \{ \.\.\.conv, title: local\.title \};\s*\}\s*return conv;\s*\}\)\s*\);', '      setConversations((prev) => {
        const remoteIds = new Set(convs.map((conv) => conv.id));

        const mergedRemote = convs.map((conv) => {
          const local = prev.find((item) => item.id === conv.id);

          if (
            local &&
            isDefaultConversationTitle(conv.title) &&
            !isDefaultConversationTitle(local.title)
          ) {
            return { ...conv, title: local.title, isOptimistic: false };
          }

          return { ...conv, isOptimistic: false };
        });

        const localOnly = prev.filter((local) =>
          !remoteIds.has(local.id) &&
          (local.id === currentConversationId || local.isOptimistic === true)
        );

        return [...localOnly, ...mergedRemote];
      });'

$Content = $Content -replace '      // Reuse the existing empty conversation instead of creating a new one\r?\n      setCurrentConversationId\(existingEmpty\.id\);', '      // Reuse the existing empty conversation instead of creating a new one
      activeConversationIdRef.current = existingEmpty.id;
      setCurrentConversation({
        id: existingEmpty.id,
        created_at: existingEmpty.created_at,
        title: existingEmpty.title || ''New Conversation'',
        messages: [],
        isOptimistic: existingEmpty.isOptimistic === true,
      });
      setCurrentConversationId(existingEmpty.id);'

$Content = $Content -replace '      const newConv = await api\.createConversation\(\);\r?\n      setConversations\(\(prev\) => \[\r?\n        \{\r?\n          id: newConv\.id,\r?\n          created_at: newConv\.created_at,\r?\n          title: newConv\.title \|\| ''New Conversation'',\r?\n          message_count: 0,\r?\n        \},\r?\n        \.\.\.prev\.filter\(\(conv\) => conv\.id !== newConv\.id\),\r?\n      \]\);\r?\n      setCurrentConversationId\(newConv\.id\);', '      const newConv = await api.createConversation();
      activeConversationIdRef.current = newConv.id;
      setCurrentConversation({
        id: newConv.id,
        created_at: newConv.created_at,
        title: newConv.title || ''New Conversation'',
        messages: [],
        isOptimistic: true,
      });
      setConversations((prev) => [
        {
          id: newConv.id,
          created_at: newConv.created_at,
          title: newConv.title || ''New Conversation'',
          message_count: 0,
          isOptimistic: true,
        },
        ...prev.filter((conv) => conv.id !== newConv.id),
      ]);
      setCurrentConversationId(newConv.id);'

$Content = $Content -replace '  const handleSelectConversation = \(id\) => \{\r?\n    setCurrentConversationId\(id\);\r?\n  \};', '  const handleSelectConversation = (id) => {
    activeConversationIdRef.current = id;
    setCurrentConversationId(id);
  };'

$Content = $Content -replace '      if \(id === currentConversationId\) \{\r?\n        setCurrentConversationId\(null\);\r?\n        setCurrentConversation\(null\);\r?\n      \}', '      if (id === currentConversationId) {
        activeConversationIdRef.current = null;
        setCurrentConversationId(null);
        setCurrentConversation(null);
      }'

$Content = $Content -replace '    const activeConversationId = currentConversationId;\r?\n\r?\n    // Optimistically update conversation title', '    const activeConversationId = currentConversationId;
    activeConversationIdRef.current = activeConversationId;

    // Optimistically update conversation title'

$Content = $Content -replace '      setCurrentConversation\(\(prev\) => \(\{\r?\n        \.\.\.prev,\r?\n        messages: \[\.\.\.prev\.messages, userMessage\],\r?\n      \}\)\);', '      setCurrentConversation((prev) => {
        const target = prev && prev.id === activeConversationId ? prev : {
          id: activeConversationId,
          title: currentTitle || ''New Conversation'',
          messages: [],
        };

        return {
          ...target,
          messages: [...(target.messages || []), userMessage],
        };
      });'

$Content = $Content -replace '      setCurrentConversation\(\(prev\) => \(\{\r?\n        \.\.\.prev,\r?\n        messages: \[\.\.\.prev\.messages, assistantMessage\],\r?\n      \}\)\);', '      setCurrentConversation((prev) => {
        const target = prev && prev.id === activeConversationId ? prev : {
          id: activeConversationId,
          title: currentTitle || ''New Conversation'',
          messages: [userMessage],
        };

        return {
          ...target,
          messages: [...(target.messages || []), assistantMessage],
        };
      });'

[IO.File]::WriteAllText($File, $Content, (New-Object System.Text.UTF8Encoding($False)))
