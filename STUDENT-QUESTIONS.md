# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:
>
> The risk is that minting and burning share one key. `SimpleStablecoin.burn` is gated only by `MINTER_ROLE`, and that function accepts any `from` address. Nothing in the token checks that the holder agreed. The vault must hold the role so `deposit` can mint, and `Vault.redeem` happens to pass `msg.sender`, but that is a choice inside the vault, not a rule of the coin. Any later call made from the vault, or any other account that receives the same role, can set a user's balance to zero. The holder cannot refuse. In a crisis that is confiscation, and it breaks the claim that redemption is the holder's own act.
>
> I would split the two powers. `mint` stays behind `MINTER_ROLE` and is called only from `Vault.deposit`, after `safeTransferFrom` has moved the collateral in. `burn` should stop taking an arbitrary `from` under that role. `SimpleStablecoin` should expose `burn(uint256 amount)`, which always burns `msg.sender` and needs no role, and `burnFrom`, which spends an allowance the holder set. `Vault.redeem` would then have the user burn their own coins, or approve the vault for that exact amount before `burnFrom`. If the allowance is missing, the call reverts. A leaked minter could still inflate supply, which is a separate failure, but it could no longer erase someone else's wallet. Redemption still works, and only with the holder's consent.

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:
>
> These three roles do different jobs, so one address should not hold all of them. `DEFAULT_ADMIN_ROLE` can grant and revoke every other role, which means it can appoint a new minter or a new pauser. In production that key belongs to a multisig behind a timelock, used rarely, and it should not also be an everyday signer. `MINTER_ROLE` belongs only to the vault contract. No externally owned account should have it. The admin grants it once at deployment and does not keep a second copy for convenience. `PAUSER_ROLE` belongs to a smaller incident-response multisig, different people from the admin, so a freeze can be decided quickly without handing those people the power to change who may mint. After deployment, a check that the admin EOA retains `MINTER_ROLE` should fail: the constructor grants it, and the deploy script should revoke it from the admin once the vault has it. The same person should not be able to print coins and to freeze withdrawals.

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:
>
> `_update` is where every balance change lands, and `whenNotPaused` sits on that function, so a pause cannot tell a transfer from a mint or a burn. Minting is the case `from == address(0)`. Burning, which is what redemption does, is the case `to == address(0)`. An ordinary transfer has both ends nonzero. To freeze transfers and new issuance but still allow exit, the pause check should narrow. While paused, revert when `from == address(0)` (no new minting) and when both `from` and `to` are nonzero (no transfers). Allow the branch `to == address(0)`, so `burn` still reaches `super._update` and `Vault.redeem` can destroy sUSD and release collateral. The pauser would then be saying "the coin cannot move or grow, but holders can still leave." That matches the reason a pause exists in a crisis: stop a bad mint or a stolen balance from circulating, without trapping the people who already hold a fully backed coin. Full code is a branch at the top of `_update`; the modifier `whenNotPaused` on the whole function has to come off.

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:
>
> In 2008, when a money-market fund broke the buck, the sponsor froze redemptions for days. That stopped a run from emptying whatever assets were left, but it also removed the only mechanism that puts a floor under the price. Holders could not turn the claim back into cash, so the secondary market had nothing to arbitrage against, and the price was just whoever would still trade a frozen claim. In March 2023, USDC traded near $0.87 after cash at Silicon Valley Bank was in doubt, and redemptions stayed open. The primary market still exchanged USDC for dollars at par, within banking hours and subject to the real reserve loss. Traders could buy the discounted coin and redeem, which pulled the market price back toward the reserve. Closing the channel protects the issuer's remaining collateral from a first-come run, and it converts a price problem into a liquidity freeze. Leaving it open admits that some of the reserve may be impaired, but it keeps the mint-redeem loop as the peg's defense. For this lab's coin, `pause()` does the 2008 thing: it freezes `redeem` together with transfers. A fully backed coin can still trade below par, because nobody can lift the collateral out. The books can be solvent and the market price can still break.

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:
>
> This coin depegs in two different ways, and the invariant `totalCollateral() >= totalSupply()` catches only one of them. The first class is a broken book. Someone mints sUSD without collateral arriving, which is what Ex3 does by granting `MINTER_ROLE` to an attacker. `totalSupply()` rises and `totalCollateral()` does not, so the inequality becomes false. The coin is no longer fully backed. A later `redeem` can revert with `InsufficientCollateral`, or it can pay out collateral that other users deposited. The second class is a blocked exit while the books still balance. `pause()` freezes redemption, the admin key is lost, or the collateral token blacklists the vault. `totalCollateral() >= totalSupply()` can remain true the whole time, and the market price can still fall, because arbitrageurs cannot run the loop that pulls the price back. Insufficient collateral and a blocked redemption channel are not the same problem. The first is solvency, and it shows up as a failed invariant. The second is permission or liquidity. The invariant stays green, and the peg breaks anyway. A test suite that only checks the inequality will miss the second class.

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:
>
> The admin calls `grantRole(MINTER_ROLE, attacker)`. That is the whole breach. The attacker then calls `mint(attacker, 1_000_000e6)`. Supply increases by one million sUSD and no mUSDC moves into the vault, so `totalCollateral()` is unchanged and `totalSupply()` is now larger. The invariant is already false at this step, before any redemption. The attacker then calls `Vault.redeem` for that full balance. `redeem` burns the attacker's sUSD and `safeTransfer`s an equal amount of mUSDC out of the vault. Those tokens were deposited by other users. The unbacked mint is paid with honest collateral, and the attacker walks away with the reserve. The step that stops this is the grant, not the redeem. `MINTER_ROLE` should be held only by the vault contract, and `mint` should be reachable only after `collateral.safeTransferFrom` succeeds inside `Vault.deposit`. An externally owned account with the role should not exist. If the role has already leaked, `revokeRole` before any `redeem` limits the damage to an inflated supply that cannot yet be cashed out. Once `redeem` is in the same transaction as the mint, the collateral is gone.

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:
>
> No. `totalCollateral()` works here only because MockUSDC is an ERC-20 sitting at the vault's address, and `balanceOf` is a fact the chain can check. A Treasury bill is not that balance. The vault would hold a claim on a custodian, a broker, or a tokenized-treasury wrapper, and the number that matters is face value or market value, not a token balance the contract can read by itself. Writing the invariant the same way would either be impossible or would trust an oracle the contract cannot audit. New problems show up immediately. Settlement is not atomic: a T-bill does not arrive in the same transaction as the mint. The custodian can refuse to pay, or can be sanctioned, while an on-chain balance still looks whole. The reported value goes stale, interest accrues, and bills mature, so "one unit of collateral equals one sUSD" is no longer an integer identity. A freeze at the custodian blocks redemption even though a `balanceOf`-style check would still pass. The invariant becomes "an off-chain attestation says the reserve covers the supply," which is the RWA problem, not a token-accounting problem.

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:
>
> A building cannot be `transfer`red into this vault, so the collateral has to be a legal claim, not the building itself. A special purpose vehicle would hold title. The on-chain token would represent a share of that vehicle, or a debt claim against it, and the vault would custody the token rather than the property. Putting it "inside" the vault means the SPV's shares are the collateral, and `totalCollateral()` becomes an attested appraised value of the building, scaled into sUSD units, not `balanceOf`. Several off-chain roles have to exist before that number means anything. A trustee or the SPV itself holds the registered title. A local land registry, or the equivalent filing, is what makes the title real. An appraiser produces the value the invariant uses, and that value expires. A lawyer writes the agreement that token holders are the beneficiaries and that a redemption is a sale of the building or of the shares, not a token transfer that returns the building in one transaction. A buyer, a delay, and a court that will enforce the SPV's documents are part of the exit. The chain can check that the attestation is on file. It cannot check that the building is still there.

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:
>
> The attack I would test next is a direct transfer of mUSDC to the vault, skipping `deposit`. The 1:1 vault does not record collateral per user. `totalCollateral()` is just `balanceOf`, and `redeem` pays from that shared pool up to the caller's sUSD balance. Anyone can `transfer` mUSDC to the vault without minting. Supply stays the same, collateral rises, and the equality breaks upward. A later redeemer can take the surplus, because the payout is not limited to what that redeemer deposited. No role is required, pause does not stop an inbound token transfer, and the contracts already allow it. That is more likely than a leaked `MINTER_ROLE`, which needs a compromised admin. The guard on `burn` can be perfect and this path still moves other people's collateral. I would add a test that transfers mUSDC straight to the vault, redeems an existing balance, and shows the redeemer received more collateral than they deposited. That single case explains why a pooled `balanceOf` is a weaker invariant than per-user collateral accounting.
