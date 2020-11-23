# Set correct subscription
Get-AzSubscription -SubscriptionName $_subscriptionName | Set-AzContext

(Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $RgName -AccountName $SaName).IPRules

$ipsToAdd = @("13.65.24.129/32",
    "13.66.138.94/31",
    "13.66.141.224/29",
    "13.66.145.80/28",
    "13.67.8.110/31")

foreach ($ip in $ipsToAdd) 
{
    if ($ip.EndsWith("/31") -or $ip.EndsWith("/32")) { continue }
    #Add-AzStorageAccountNetworkRule -ResourceGroupName $RgName -AccountName $SaName -IPAddressOrRange $ip
    Remove-AzStorageAccountNetworkRule -ResourceGroupName $RgName -AccountName $SaName -IPAddressOrRange $ip
}
